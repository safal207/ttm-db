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

pub trait TraceStore {
    fn append(&mut self, record: TraceRecord) -> Result<(), String>;
    fn iter(&self) -> Box<dyn Iterator<Item = &TraceRecord> + '_>;
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
            Self { records: Vec::new() }
        }
    }

    impl TraceStore for InMemoryStore {
        fn append(&mut self, record: TraceRecord) -> Result<(), String> {
            self.records.push(record);
            Ok(())
        }

        fn iter(&self) -> Box<dyn Iterator<Item = &TraceRecord> + '_> {
            Box::new(self.records.iter())
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
        let record = TraceRecord {
            thread_id: "thread-1".to_string(),
            transition_id: "t-1".to_string(),
            ts: "now".to_string(),
            from_state_ref: "a".to_string(),
            to_state_ref: "b".to_string(),
            admissibility: "rule".to_string(),
            confidence: 1.0,
            lane: "main".to_string(),
            seal: None,
            metadata: HashMap::new(),
        };

        assert!(store.append(record).is_ok());
        assert_eq!(store.iter().count(), 1);
    }

    #[test]
    fn projection_rebuild_consumes_stream() {
        let mut store = InMemoryStore::new();
        for idx in 0..3 {
            let record = TraceRecord {
                thread_id: "thread-1".to_string(),
                transition_id: format!("t-{idx}"),
                ts: "now".to_string(),
                from_state_ref: "a".to_string(),
                to_state_ref: "b".to_string(),
                admissibility: "rule".to_string(),
                confidence: 1.0,
                lane: "main".to_string(),
                seal: None,
                metadata: HashMap::new(),
            };
            store.append(record).unwrap();
        }

        let mut projection = CountingProjection::new();
        for record in store.iter() {
            projection.apply(record);
        }

        assert_eq!(projection.count, 3);
    }
}
