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

package main

import (
	"fmt"
	"log"
	"net"
	"strings"

	"github.com/coreos/go-systemd/v22/activation"
	"github.com/coreos/go-systemd/v22/daemon"
	"github.com/coreos/go-systemd/v22/journal"
)

const (
	bufferSize      = 1024
	localServerPort = 514
)

type priName struct {
	name string
	val  journal.Priority
}

var priorityNames = []priName{
	{"emerg", journal.PriEmerg},
	{"alert", journal.PriAlert},
	{"crit", journal.PriCrit},
	{"err", journal.PriErr},
	{"warning", journal.PriWarning},
	{"notice", journal.PriNotice},
	{"info", journal.PriInfo},
	{"debug", journal.PriDebug},
}

func main() {
	listeners, err := activation.PacketConns()
	if err != nil {
		log.Fatalf("cannot get listeners: %v", err)
	}

	var conn net.PacketConn
	if len(listeners) > 1 {
		log.Fatalf("too many file descriptors received")
	}

	if len(listeners) == 1 {
		conn = listeners[0]
	} else {
		addr := &net.UDPAddr{
			IP:   net.ParseIP("::"),
			Port: localServerPort,
		}
		conn, err = net.ListenUDP("udp", addr)
		if err != nil {
			log.Fatalf("could not bind on port %d: %v", localServerPort, err)
		}
	}
	defer conn.Close()

	daemon.SdNotify(false, daemon.SdNotifyReady)
	daemon.SdNotify(false, "STATUS=Listening for syslog input...")

	var count uint64
	buf := make([]byte, bufferSize)

	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			log.Printf("could not receive data: %v", err)
			continue
		}

		var ip net.IP
		switch a := addr.(type) {
		case *net.UDPAddr:
			ip = a.IP
		default:
			log.Printf("received data from unkown address type: %T", addr)
			continue
		}

		msg := string(buf[:n])
		priority := journal.PriInfo

		// Parse priority like the C code
		firstPart := msg
		if space := strings.Index(msg, " "); space != -1 {
			firstPart = msg[:space]
		}

		for _, p := range priorityNames {
			if strings.Contains(firstPart, p.name) {
				priority = p.val
				break
			}
		}

		err = journal.Send(msg, priority, map[string]string{
			"SYSLOG_IDENTIFIER": ip.String(),
		})
		if err != nil {
			log.Printf("could not send to journal: %v", err)
			continue
		}

		count++
		daemon.SdNotify(false, fmt.Sprintf("STATUS=Forwarded %d syslog messages.", count))
	}
}
