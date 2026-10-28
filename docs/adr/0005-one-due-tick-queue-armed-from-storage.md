# One due-tick queue, armed from storage

The mod has no unconditional `on_tick`. Engine events drive the work, and one due-tick queue holds everything that must happen later: a project's next advance, an instance's recount, a stall deadline, a materials retry. Its `on_nth_tick` handler is registered only while the queue holds work, `storage.queue_armed` records that it is, and `on_load` registers it again from that flag alone.

Land Title Registry learned the hard way why the last part matters: a client joining a running game runs `on_load` while the server does not, so any registration that is not a pure function of storage makes the two hold different handler sets, and Factorio refuses the join as a handler mismatch.

Supporting choices:

- **A materials wait is a timer, by necessity.** No engine event says items arrived in a logistic network. Capacity waits reopen on instance completion instead, and chunk waits request the chunks and wake on `on_chunk_generated`.
- **Work kinds are registered at load time.** The queue stores plain tables (`{kind = "recount", id = 7}`), never functions.
- **An empty queue's minimum is nil, not infinity.** Nothing infinite or NaN goes into storage.
