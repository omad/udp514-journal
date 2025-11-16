/*
 * (C) 2025 by Jules
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *
 */

use anyhow::{bail, Context, Result};
use std::net::UdpSocket;
use std::os::unix::io::FromRawFd;
use systemd::daemon;
use systemd::journal;

const BUFFER_SIZE: usize = 1024;
const LOCAL_SERVER_PORT: u16 = 514;

fn main() -> Result<()> {
    let fds = daemon::listen_fds(false)?;

    let socket: UdpSocket = if fds.len() > 1 {
        bail!("too many file descriptors received");
    } else if fds.len() == 1 {
        // LISTEN_FDS_START is private, but it's always 3.
        unsafe { FromRawFd::from_raw_fd(3) }
    } else {
        UdpSocket::bind(format!("[::]:{}", LOCAL_SERVER_PORT))
            .context(format!("could not bind on port {}", LOCAL_SERVER_PORT))?
    };

    daemon::notify(false, [(daemon::STATE_READY, "1")].iter())?;
    daemon::notify(
        false,
        [(daemon::STATE_STATUS, "Listening for syslog input...")].iter(),
    )?;

    let mut count = 0;
    let mut buf = [0; BUFFER_SIZE];

    loop {
        let (n, addr) = socket
            .recv_from(&mut buf)
            .context("could not receive data")?;

        let msg = std::str::from_utf8(&buf[..n])?;
        // Using integer literals for log levels as the constants are not found.
        let priority = msg
            .split(' ')
            .next()
            .and_then(|part| {
                if part.contains("emerg") {
                    Some(0) // LOG_EMERG
                } else if part.contains("alert") {
                    Some(1) // LOG_ALERT
                } else if part.contains("crit") {
                    Some(2) // LOG_CRIT
                } else if part.contains("err") {
                    Some(3) // LOG_ERR
                } else if part.contains("warning") {
                    Some(4) // LOG_WARNING
                } else if part.contains("notice") {
                    Some(5) // LOG_NOTICE
                } else if part.contains("info") {
                    Some(6) // LOG_INFO
                } else if part.contains("debug") {
                    Some(7) // LOG_DEBUG
                } else {
                    None
                }
            })
            .unwrap_or(6); // LOG_INFO

        let priority_str = format!("PRIORITY={}", priority);
        let syslog_identifier_str = format!("SYSLOG_IDENTIFIER={}", addr.ip());
        let message_str = format!("MESSAGE={}", msg);

        journal::send(&[
            &message_str,
            &priority_str,
            &syslog_identifier_str,
        ]);

        count += 1;
        daemon::notify(
            false,
            [(
                daemon::STATE_STATUS,
                &format!("Forwarded {} syslog messages.", count),
            )]
            .iter(),
        )?;
    }
}
