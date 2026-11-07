//! Loopback HTTP servers for tests.
//!
//! Tools that watch for new local ports, such as an IDE's or agent host's
//! port detection, connect to every listener within about a second, with
//! `GET /` or a TLS handshake. A fixture that answers such a connection
//! instead of its client hands the client a closed or misordered
//! conversation. No client under test requests the root or speaks TLS to a
//! fixture, so fixtures drop such connections.
use std::net::{TcpListener, TcpStream};
use std::thread;
use std::time::{Duration, Instant};

const ROOT_REQUEST: &[u8] = b"GET / ";
/// A TLS handshake record of any protocol version.
const TLS_HANDSHAKE: &[u8] = &[0x16, 0x03];

/// Whether `stream` carries a port probe rather than the client under test.
/// The request stays unread, and the stream blocking without a read timeout.
pub(crate) fn is_port_probe(stream: &TcpStream) -> bool {
    let _ = stream.set_nonblocking(false);
    let deadline = Instant::now() + Duration::from_secs(2);
    let mut head = [0_u8; ROOT_REQUEST.len()];
    let probe = loop {
        let Some(remaining) = deadline.checked_duration_since(Instant::now()) else {
            break false;
        };
        let _ = stream.set_read_timeout(Some(remaining));
        let read = match stream.peek(&mut head) {
            Ok(0) | Err(_) => break false,
            Ok(read) => read,
        };
        let head = &head[..read];
        let could_be = |probe: &[u8]| probe.starts_with(head) || head.starts_with(probe);
        if head.starts_with(TLS_HANDSHAKE) || head.starts_with(ROOT_REQUEST) {
            break true;
        }
        if !could_be(TLS_HANDSHAKE) && !could_be(ROOT_REQUEST) {
            break false;
        }
        // Only part of the request arrived yet.
        thread::sleep(Duration::from_millis(5));
    };
    let _ = stream.set_read_timeout(None);
    probe
}

/// Accepts the next connection that is not a port probe.
pub(crate) fn accept_client(listener: &TcpListener) -> TcpStream {
    loop {
        let (stream, _) = listener.accept().unwrap();
        if !is_port_probe(&stream) {
            return stream;
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};

    #[test]
    fn probes_are_skipped_and_the_client_request_stays_unread() {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let address = listener.local_addr().unwrap();
        let mut root = TcpStream::connect(address).unwrap();
        root.write_all(b"GET / HTTP/1.1\r\nhost: localhost\r\n\r\n")
            .unwrap();
        let mut tls = TcpStream::connect(address).unwrap();
        tls.write_all(&[0x16, 0x03, 0x01, 0x05, 0x00, 0x01])
            .unwrap();
        let mut client = TcpStream::connect(address).unwrap();
        // A request line that arrives in pieces is still told apart.
        client.write_all(b"GET /").unwrap();
        let writer = thread::spawn(move || {
            thread::sleep(Duration::from_millis(20));
            client.write_all(b"oauth HTTP/1.1\r\n\r\n").unwrap();
            client
        });
        let mut accepted = accept_client(&listener);
        let _client = writer.join().unwrap();
        let mut request = [0_u8; 19];
        accepted.read_exact(&mut request).unwrap();
        assert_eq!(&request, b"GET /oauth HTTP/1.1");
    }
}
