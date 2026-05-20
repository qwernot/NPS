package pmux

import (
	"io"
	"net"
	"strconv"
	"strings"
	"testing"
	"time"
)

func getFreePort(t *testing.T) int {
	t.Helper()
	l, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer l.Close()
	return l.Addr().(*net.TCPAddr).Port
}

func TestPortMux_HTTP(t *testing.T) {
	pMux := NewPortMux(getFreePort(t), "manager.local")
	defer pMux.Close()

	done := make(chan error, 1)
	go func() {
		conn, err := net.Dial("tcp", "127.0.0.1:"+strconv.Itoa(pMux.port))
		if err != nil {
			done <- err
			return
		}
		defer conn.Close()
		_, err = io.WriteString(conn, "GET / HTTP/1.1\r\nHost: example.local\r\n\r\n")
		done <- err
	}()

	accepted := make(chan net.Conn, 1)
	errCh := make(chan error, 1)
	go func() {
		conn, err := pMux.GetHttpListener().Accept()
		if err != nil {
			errCh <- err
			return
		}
		accepted <- conn
	}()

	select {
	case err := <-done:
		if err != nil {
			t.Fatal(err)
		}
	case <-time.After(time.Second):
		t.Fatal("dial timed out")
	}

	select {
	case err := <-errCh:
		t.Fatal(err)
	case conn := <-accepted:
		defer conn.Close()
		buf := make([]byte, len("GET"))
		if _, err := io.ReadFull(conn, buf); err != nil {
			t.Fatal(err)
		}
		if !strings.EqualFold(string(buf), "GET") {
			t.Fatalf("unexpected prefix %q", string(buf))
		}
	case <-time.After(time.Second):
		t.Fatal("accept timed out")
	}
}
