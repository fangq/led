#!/usr/bin/env python3
"""Run notebook cells in a real Jupyter kernel, for LED.

LED drives this the way it drives gdb: a subprocess speaking a line protocol
over stdin and stdout.  One JSON object per line, in both directions, so a
reader never has to guess where a message ends -- JSON escapes its own
newlines, and nothing else here writes any.

Why a helper at all, rather than talking to the kernel from the editor: a
kernel is reached over ZeroMQ with a wire protocol, HMAC-signed messages and
five sockets, and jupyter_client already does all of it, correctly, in the
Python that the kernels themselves are installed for.  Writing that again in
Pascal would be a great deal of code whose only advantage is being written in
Pascal.  This way LED needs no ZeroMQ binding, and every kernel the reader
has installed works -- python3, octave, whatever else -- because none of it
is special-cased here.

It also means the magics work.  %%octave, %matplotlib inline, !pip install:
those are IPython's, handled inside the kernel, and an editor that sends the
cell's text as the cell's text gets them for free.

Commands in (one per line):

    {"cmd": "run", "id": 7, "code": "print(1)"}
    {"cmd": "interrupt"}
    {"cmd": "restart"}
    {"cmd": "shutdown"}

Events out (one per line):

    {"ev": "ready", "kernel": "python3", "language": "python"}
    {"ev": "status", "state": "busy"}
    {"ev": "output", "id": 7, "output": {...}}   an nbformat output object
    {"ev": "done", "id": 7, "status": "ok", "count": 3}
    {"ev": "failed", "msg": "..."}

The outputs are built in nbformat's own shape here rather than in the editor,
because this is the side that has nbformat's definition of it to hand.  LED
appends what it is given to the cell.
"""

import json
import sys
import threading
import queue


def emit(**event):
    """One event, one line, flushed: the editor is waiting on this pipe."""
    sys.stdout.write(json.dumps(event, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def fail(msg):
    emit(ev="failed", msg=msg)
    sys.exit(1)


def lines_of(text):
    """Text as nbformat stores it: a list of lines with their newlines kept.

    nbformat's own split_lines, near enough, and the shape LED's reader
    expects -- it joins the list with nothing between.
    """
    if not text:
        return []
    out = text.splitlines(keepends=True)
    return out


def output_from(msg):
    """An nbformat output object from a kernel iopub message, or None."""
    kind = msg["header"]["msg_type"]
    content = msg["content"]

    if kind == "stream":
        return {
            "output_type": "stream",
            "name": content.get("name", "stdout"),
            "text": lines_of(content.get("text", "")),
        }

    if kind in ("execute_result", "display_data"):
        data = dict(content.get("data", {}))
        # Text stays a list of lines, as nbformat writes it; a picture stays
        # the single base64 string it arrived as.
        for mime in list(data):
            if mime.startswith("text/") and isinstance(data[mime], str):
                data[mime] = lines_of(data[mime])
        out = {
            "output_type": kind,
            "data": data,
            "metadata": content.get("metadata", {}),
        }
        if kind == "execute_result":
            out["execution_count"] = content.get("execution_count")
        return out

    if kind == "error":
        return {
            "output_type": "error",
            "ename": content.get("ename", ""),
            "evalue": content.get("evalue", ""),
            "traceback": content.get("traceback", []),
        }

    return None


def main():
    if len(sys.argv) < 2:
        fail("no kernel named")
    name = sys.argv[1]

    try:
        from jupyter_client.manager import KernelManager
    except Exception as e:                                   # noqa: BLE001
        # The common case, and worth a sentence rather than a traceback: the
        # reader has Python but not the Jupyter client library.
        fail("jupyter_client is not installed for %s (%s)"
             % (sys.executable, e))

    km = KernelManager(kernel_name=name)
    try:
        km.start_kernel()
    except Exception as e:                                   # noqa: BLE001
        fail("the %s kernel would not start (%s)" % (name, e))

    kc = km.client()
    kc.start_channels()
    try:
        kc.wait_for_ready(timeout=60)
    except Exception as e:                                   # noqa: BLE001
        fail("the %s kernel did not become ready (%s)" % (name, e))

    info = {}
    try:
        kc.kernel_info()
        reply = kc.get_shell_msg(timeout=10)
        info = reply["content"].get("language_info", {})
    except Exception:                                        # noqa: BLE001
        pass

    emit(ev="ready", kernel=name, language=info.get("name", ""))

    # Commands are read on a thread of their own so that a long-running cell
    # does not make the editor's interrupt wait for it.
    commands = queue.Queue()

    def read_commands():
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            try:
                commands.put(json.loads(line))
            except ValueError:
                emit(ev="failed", msg="a command was not JSON")
        commands.put({"cmd": "shutdown"})

    threading.Thread(target=read_commands, daemon=True).start()

    while True:
        cmd = commands.get()
        what = cmd.get("cmd", "")

        if what == "shutdown":
            break

        if what == "interrupt":
            km.interrupt_kernel()
            continue

        if what == "restart":
            km.restart_kernel(now=False)
            kc.stop_channels()
            kc = km.client()
            kc.start_channels()
            try:
                kc.wait_for_ready(timeout=60)
            except Exception as e:                           # noqa: BLE001
                emit(ev="failed", msg="the kernel would not come back (%s)" % e)
                break
            emit(ev="ready", kernel=name, language=info.get("name", ""))
            continue

        if what != "run":
            emit(ev="failed", msg="unknown command %r" % what)
            continue

        run_id = cmd.get("id", 0)
        code = cmd.get("code", "")

        # allow_stdin is off: a cell that asks for input would otherwise stop
        # the kernel dead waiting for an answer nobody can give it.  The
        # kernel raises StdinNotImplementedError instead, which arrives as an
        # ordinary error output and says exactly that.
        msg_id = kc.execute(code, allow_stdin=False)
        count = None
        status = "ok"

        while True:
            try:
                msg = kc.get_iopub_msg(timeout=0.2)
            except queue.Empty:
                # Nothing from the kernel for a moment.  Commands that arrive
                # meanwhile -- an interrupt, most of all -- are acted on here
                # rather than after the cell finishes.
                try:
                    pending = commands.get_nowait()
                except queue.Empty:
                    continue
                if pending.get("cmd") == "interrupt":
                    km.interrupt_kernel()
                else:
                    commands.put(pending)
                continue

            parent = msg.get("parent_header", {}).get("msg_id")
            if parent != msg_id:
                continue

            kind = msg["header"]["msg_type"]

            if kind == "status":
                state = msg["content"].get("execution_state", "")
                emit(ev="status", state=state)
                if state == "idle":
                    break
                continue

            if kind == "execute_input":
                count = msg["content"].get("execution_count")
                continue

            if kind == "error":
                status = "error"

            out = output_from(msg)
            if out is not None:
                emit(ev="output", id=run_id, output=out)

        emit(ev="done", id=run_id, status=status, count=count)

    try:
        kc.stop_channels()
        km.shutdown_kernel(now=True)
    except Exception:                                        # noqa: BLE001
        pass


if __name__ == "__main__":
    main()
