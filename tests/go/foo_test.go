package foo

import (
	"reflect"
	"testing"
)

func assertEquals(t testing.TB, expected, actual any) {
	t.Helper()

	if !reflect.DeepEqual(expected, actual) {
		t.Errorf("should be\n'%v'\nbut was\n'%v'",  expected, actual)
	}
}

func TestSuccess(t *testing.T) {
	assertEquals(t, "success", "success")
}

func TestFailure(t *testing.T) {
	assertEquals(t, "success", "failure")
}
