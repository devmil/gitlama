//! Domain values: no Git process, persistence, FRB or wire dependency. Application use cases
//! return these; the FRB facade and the wire adapter translate them.
pub mod facts;
pub mod failure;
pub mod history;
pub mod hosting;
pub mod ids;
pub mod limits;
pub mod outcome;
pub mod path_identity;
pub mod session_policy;
