use super::*;

#[test]
fn a_peer_is_named_the_way_the_send_command_resolves_it() {
    let status = r#"{"Peer":{"nodekey:aa":{"DNSName":"macbookair.tail1234.ts.net.","HostName":"macbookair","Online":true},
                             "nodekey:bb":{"DNSName":"","HostName":"iphone"},
                             "nodekey:cc":{"DNSName":"se-mma-wg-001.mullvad.ts.net.","HostName":"se-mma"}}}"#;
    assert_eq!(peer_names(status), vec!["iphone".to_string(), "macbookair.tail1234.ts.net".to_string()],
               "an exit-node relay is never a send target");
    assert!(peer_names("not json at all").is_empty());
    assert!(peer_names(r#"{"Self":{"HostName":"minipc"}}"#).is_empty(), "a tailnet of one has no peer to send to");
}

// A hundred archives of one date is refused rather than written over the first of them.