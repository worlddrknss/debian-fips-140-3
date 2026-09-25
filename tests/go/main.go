// Command fipscheck reports whether the Go FIPS 140-3 module is active and
// enforcing. It exits non-zero on any failure.
package main

import (
	"crypto/fips140"
	"crypto/md5"
	"crypto/sha256"
	"fmt"
	"os"
)

func main() {
	if !fips140.Enabled() {
		fail("FIPS 140-3 mode is not enabled")
	}
	pass("FIPS 140-3 mode is enabled")

	sha256.Sum256([]byte("test"))
	pass("approved algorithm SHA-256 works")

	if md5Allowed() {
		fail("MD5 succeeded under fips140=only")
	}
	pass("non-approved algorithm MD5 is rejected")
}

func md5Allowed() (ok bool) {
	defer func() {
		if recover() != nil {
			ok = false
		}
	}()
	md5.Sum([]byte("test"))
	return true
}

func pass(msg string) { fmt.Println("PASS:", msg) }

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "FAIL:", msg)
	os.Exit(1)
}
