package config

import (
	"log"
	"regexp"
	"testing"
)

func TestReg(t *testing.T) {
	content := `
[common]
server=127.0.0.1:8284
tp=tcp
vkey=123
[web2]
host=www.baidu.com
host_change=www.sina.com
target=127.0.0.1:8080,127.0.0.1:8082
header_cookkile=122123
header_user-Agent=122123
[web2]
host=www.baidu.com
host_change=www.sina.com
target=127.0.0.1:8080,127.0.0.1:8082
header_cookkile="122123"
header_user-Agent=122123
[tunnel1]
type=udp
target=127.0.0.1:8080
port=9001
compress=snappy
crypt=true
u=1
p=2
[tunnel2]
type=tcp
target=127.0.0.1:8080
port=9001
compress=snappy
crypt=true
u=1
p=2
`
	re, err := regexp.Compile(`\[.+?\]`)
	if err != nil {
		t.Fail()
	}
	log.Println(re.FindAllString(content, -1))
}

func TestDealCommon(t *testing.T) {
	s := `server=127.0.0.1:8284
tp=tcp
vkey=123`
	c := dealCommon(s)
	if c.Server != "127.0.0.1:8284" {
		t.Fatalf("server = %q", c.Server)
	}
	if c.Tp != "tcp" {
		t.Fatalf("tp = %q", c.Tp)
	}
	if c.VKey != "123" {
		t.Fatalf("vkey = %q", c.VKey)
	}
	if c.Client == nil || c.Client.Cnf == nil || c.Client.Flow == nil {
		t.Fatal("client defaults were not initialized")
	}
}

func TestGetTitleContent(t *testing.T) {
	s := "[common]"
	if getTitleContent(s) != "common" {
		t.Fail()
	}
}
