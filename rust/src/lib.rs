//! Core traits for TTM DB.

use std::collections::HashMap;

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TraceRecord {
    pub thread_id: String,
    pub transition_id: String,
    pub ts: String,
    pub from_state_ref: String,
    pub to_state_ref: String,
    pub admissibility: String,
    pub confidence: f64,
    pub lane: String,
    pub seal: Option<String>,
    pub metadata: HashMap<String, String>,
}

#[derive(Debug, Clone, PartialEq)]
pub enum VerificationStatus {
    Verified,
    Unverified,
    Failed,
    Unknown,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TraceEnvelope {
    pub record: TraceRecord,
    pub verification_status: VerificationStatus,
    pub verification_error: Option<String>,
}

pub trait TraceVerifier {
    fn verify(&self, record: &TraceRecord) -> Result<(), String>;
}

pub fn envelope_unverified(record: TraceRecord) -> TraceEnvelope {
    TraceEnvelope {
        record,
        verification_status: VerificationStatus::Unverified,
        verification_error: None,
    }
}

pub fn envelope_with_verifier(record: TraceRecord, verifier: &impl TraceVerifier) -> TraceEnvelope {
    match verifier.verify(&record) {
        Ok(()) => TraceEnvelope {
            record,
            verification_status: VerificationStatus::Verified,
            verification_error: None,
        },
        Err(error) => TraceEnvelope {
            record,
            verification_status: VerificationStatus::Failed,
            verification_error: Some(error),
        },
    }
}

#[derive(Debug, Clone, Default, PartialEq)]
pub struct TraceQuery {
    pub thread_id: Option<String>,
    pub lane: Option<String>,
    pub limit: Option<usize>,
}

pub trait TraceStore {
    fn append(&mut self, record: TraceRecord) -> Result<(), String>;
    fn iter(&self, query: TraceQuery) -> Box<dyn Iterator<Item = &TraceRecord> + '_>;
}

pub trait Projection {
    fn name(&self) -> &str;
    fn apply(&mut self, record: &TraceRecord);
    fn finalize(&mut self) {}
}

#[cfg(test)]
mod tests {
    use super::*;

    struct InMemoryStore {
        records: Vec<TraceRecord>,
    }

    impl InMemoryStore {
        fn new() -> Self {
            Self {
                records: Vec::new(),
            }
        }
    }

    impl TraceStore for InMemoryStore {
        fn append(&mut self, record: TraceRecord) -> Result<(), String> {
            self.records.push(record);
            Ok(())
        }

        fn iter(&self, query: TraceQuery) -> Box<dyn Iterator<Item = &TraceRecord> + '_> {
            let TraceQuery {
                thread_id,
                lane,
                limit,
            } = query;

            let iter = self.records.iter().filter(move |record| {
                thread_id
                    .as_ref()
                    .map_or(true, |thread_id| &record.thread_id == thread_id)
                    && lane.as_ref().map_or(true, |lane| &record.lane == lane)
            });

            match limit {
                Some(limit) => Box::new(iter.take(limit)),
                None => Box::new(iter),
            }
        }
    }

    struct CountingProjection {
        count: usize,
    }

    impl CountingProjection {
        fn new() -> Self {
            Self { count: 0 }
        }
    }

    impl Projection for CountingProjection {
        fn name(&self) -> &str {
            "counting"
        }

        fn apply(&mut self, _record: &TraceRecord) {
            self.count += 1;
        }
    }

    #[test]
    fn append_adds_records() {
        let mut store = InMemoryStore::new();
        let record = trace_record("thread-1", "t-1", "main");

        assert!(store.append(record).is_ok());
        assert_eq!(store.iter(TraceQuery::default()).count(), 1);
    }

    #[test]
    fn iter_filters_by_thread_id() {
        let mut store = seeded_store();
        store
            .append(trace_record("thread-2", "t-4", "main"))
            .unwrap();

        let records: Vec<_> = store
            .iter(TraceQuery {
                thread_id: Some("thread-2".to_string()),
                ..TraceQuery::default()
            })
            .collect();

        assert_eq!(records.len(), 1);
        assert_eq!(records[0].transition_id, "t-4");
    }

    #[test]
    fn iter_filters_by_lane() {
        let store = seeded_store();

        let records: Vec<_> = store
            .iter(TraceQuery {
                lane: Some("shadow".to_string()),
                ..TraceQuery::default()
            })
            .collect();

        assert_eq!(records.len(), 1);
        assert_eq!(records[0].transition_id, "t-3");
    }

    #[test]
    fn iter_applies_limit() {
        let store = seeded_store();

        let records: Vec<_> = store
            .iter(TraceQuery {
                limit: Some(2),
                ..TraceQuery::default()
            })
            .collect();

        assert_eq!(records.len(), 2);
        assert_eq!(records[0].transition_id, "t-1");
        assert_eq!(records[1].transition_id, "t-2");
    }

    #[test]
    fn iter_preserves_append_order_after_filtering() {
        let store = seeded_store();

        let ids: Vec<_> = store
            .iter(TraceQuery {
                lane: Some("main".to_string()),
                ..TraceQuery::default()
            })
            .map(|record| record.transition_id.as_str())
            .collect();

        assert_eq!(ids, vec!["t-1", "t-2"]);
    }

    #[test]
    fn envelope_unverified_marks_record_as_unverified() {
        let record = trace_record("thread-1", "t-1", "main");
        let envelope = envelope_unverified(record.clone());

        assert_eq!(
            envelope,
            TraceEnvelope {
                record,
                verification_status: VerificationStatus::Unverified,
                verification_error: None,
            }
        );
    }

    #[test]
    fn envelope_with_verifier_maps_success_and_error() {
        struct StubVerifier;

        impl TraceVerifier for StubVerifier {
            fn verify(&self, record: &TraceRecord) -> Result<(), String> {
                if record.transition_id == "ok" {
                    Ok(())
                } else {
                    Err("invalid_seal".to_string())
                }
            }
        }

        let verifier = StubVerifier;

        let verified = envelope_with_verifier(trace_record("thread-1", "ok", "main"), &verifier);
        assert_eq!(verified.verification_status, VerificationStatus::Verified);
        assert_eq!(verified.verification_error, None);

        let failed = envelope_with_verifier(trace_record("thread-1", "bad", "main"), &verifier);
        assert_eq!(failed.verification_status, VerificationStatus::Failed);
        assert_eq!(failed.verification_error, Some("invalid_seal".to_string()));
    }

    #[test]
    fn deterministic_projection_rebuild_from_same_query() {
        let store = seeded_store();
        let query = TraceQuery {
            lane: Some("main".to_string()),
            ..TraceQuery::default()
        };

        let first = rebuild_counting(&store, query.clone());
        let second = rebuild_counting(&store, query);

        assert_eq!(first, second);
    }

    fn rebuild_counting(store: &impl TraceStore, query: TraceQuery) -> usize {
        let mut projection = CountingProjection::new();
        for record in store.iter(query) {
            projection.apply(record);
        }
        projection.count
    }

    fn seeded_store() -> InMemoryStore {
        let mut store = InMemoryStore::new();
        store
            .append(trace_record("thread-1", "t-1", "main"))
            .unwrap();
        store
            .append(trace_record("thread-1", "t-2", "main"))
            .unwrap();
        store
            .append(trace_record("thread-1", "t-3", "shadow"))
            .unwrap();
        store
    }

    fn trace_record(thread_id: &str, transition_id: &str, lane: &str) -> TraceRecord {
        TraceRecord {
            thread_id: thread_id.to_string(),
            transition_id: transition_id.to_string(),
            ts: "now".to_string(),
            from_state_ref: "a".to_string(),
            to_state_ref: "b".to_string(),
            admissibility: "rule".to_string(),
            confidence: 1.0,
            lane: lane.to_string(),
            seal: None,
            metadata: HashMap::new(),
        }
    }
}
