# Glossary

- **trace:** an append-only record of a recognized transition.
- **transition:** a change from one state reference to another.
- **recognized:** admitted as valid according to admissibility rules.
- **admissibility:** the rationale or rule set that admits a transition as a trace.
- **confidence:** a 0..1 value expressing confidence in recognition.
- **projection:** a derived, rebuildable view computed from traces.
- **view:** the materialized or computed result of a projection.
- **life line / thread:** a continuity thread identified by `thread_id`.
- **lane:** domain or life-line lane.
- **seal:** an integrity hook (e.g., hash) over the trace record.
- **verification:** validating a seal according to T-Trace rules.
