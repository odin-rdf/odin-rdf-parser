package iri

import "core:mem"
import "core:testing"

import rdf "../.."

RFC_BASE :: "http://a/b/c/d;p?q"

resolve_one :: proc(t: ^testing.T, base, ref, want: string, loc := #caller_location) {
	table: rdf.Intern_Table
	rdf.intern_table_init(&table)
	defer rdf.intern_table_destroy(&table)
	scratch: Scratch
	defer scratch_destroy(&scratch)

	got, ok := resolve(&table, base, ref, &scratch)
	testing.expectf(t, ok, "%q against %q: not ok", ref, base, loc = loc)
	testing.expectf(t, got == want, "%q against %q: got %q, want %q", ref, base, got, want, loc = loc)
}

@(test)
test_rfc3986_normal_examples :: proc(t: ^testing.T) {
	cases := [?][2]string {
		{"g:h", "g:h"},
		{"g", "http://a/b/c/g"},
		{"./g", "http://a/b/c/g"},
		{"g/", "http://a/b/c/g/"},
		{"/g", "http://a/g"},
		{"//g", "http://g"},
		{"?y", "http://a/b/c/d;p?y"},
		{"g?y", "http://a/b/c/g?y"},
		{"#s", "http://a/b/c/d;p?q#s"},
		{"g#s", "http://a/b/c/g#s"},
		{"g?y#s", "http://a/b/c/g?y#s"},
		{";x", "http://a/b/c/;x"},
		{"g;x", "http://a/b/c/g;x"},
		{"g;x?y#s", "http://a/b/c/g;x?y#s"},
		{"", "http://a/b/c/d;p?q"},
		{".", "http://a/b/c/"},
		{"./", "http://a/b/c/"},
		{"..", "http://a/b/"},
		{"../", "http://a/b/"},
		{"../g", "http://a/b/g"},
		{"../..", "http://a/"},
		{"../../", "http://a/"},
		{"../../g", "http://a/g"},
	}
	for c in cases {
		resolve_one(t, RFC_BASE, c[0], c[1])
	}
}

@(test)
test_rfc3986_abnormal_examples :: proc(t: ^testing.T) {
	cases := [?][2]string {
		{"../../../g", "http://a/g"},
		{"../../../../g", "http://a/g"},
		{"/./g", "http://a/g"},
		{"/../g", "http://a/g"},
		{"g.", "http://a/b/c/g."},
		{".g", "http://a/b/c/.g"},
		{"g..", "http://a/b/c/g.."},
		{"..g", "http://a/b/c/..g"},
		{"./../g", "http://a/b/g"},
		{"./g/.", "http://a/b/c/g/"},
		{"g/./h", "http://a/b/c/g/h"},
		{"g/../h", "http://a/b/c/h"},
		{"g;x=1/./y", "http://a/b/c/g;x=1/y"},
		{"g;x=1/../y", "http://a/b/c/y"},
		{"g?y/./x", "http://a/b/c/g?y/./x"},
		{"g?y/../x", "http://a/b/c/g?y/../x"},
		{"g#s/./x", "http://a/b/c/g#s/./x"},
		{"g#s/../x", "http://a/b/c/g#s/../x"},
		{"http:g", "http:g"}, // strict parser, no backwards-compat merge
	}
	for c in cases {
		resolve_one(t, RFC_BASE, c[0], c[1])
	}
}

@(test)
test_reference_classes :: proc(t: ^testing.T) {
	// Authority-bearing base with an empty path exercises the '/'-merge
	// branch; fragment-only and empty references keep base components.
	resolve_one(t, "http://example.org", "g", "http://example.org/g")
	resolve_one(t, "http://example.org", "", "http://example.org")
	resolve_one(t, "http://example.org/d?q", "#f", "http://example.org/d?q#f")
	resolve_one(t, "http://example.org/d", "//other.net/x", "http://other.net/x")
	resolve_one(t, "urn:isbn:0451450523", "urn:oid:1.2.3", "urn:oid:1.2.3")
	// Scheme-less base with a relative reference cannot resolve.
	table: rdf.Intern_Table
	rdf.intern_table_init(&table)
	defer rdf.intern_table_destroy(&table)
	scratch: Scratch
	defer scratch_destroy(&scratch)
	_, ok := resolve(&table, "", "g", &scratch)
	testing.expect(t, !ok, "relative ref against empty base must fail")
	abs, abs_ok := resolve(&table, "", "http://a/g", &scratch)
	testing.expect(t, abs_ok, "absolute ref needs no base")
	testing.expect_value(t, abs, "http://a/g")
}

@(test)
test_base_chaining :: proc(t: ^testing.T) {
	// Each @base resolves against the base in effect at that point.
	table: rdf.Intern_Table
	rdf.intern_table_init(&table)
	defer rdf.intern_table_destroy(&table)
	scratch: Scratch
	defer scratch_destroy(&scratch)

	base1, ok1 := resolve(&table, "", "http://example.org/dir/doc", &scratch)
	testing.expect(t, ok1)
	base2, ok2 := resolve(&table, base1, "sub/", &scratch)
	testing.expect(t, ok2)
	testing.expect_value(t, base2, "http://example.org/dir/sub/")
	base3, ok3 := resolve(&table, base2, "../other/", &scratch)
	testing.expect(t, ok3)
	testing.expect_value(t, base3, "http://example.org/dir/other/")
	leaf, ok4 := resolve(&table, base3, "x", &scratch)
	testing.expect(t, ok4)
	testing.expect_value(t, leaf, "http://example.org/dir/other/x")
}

@(test)
test_repeat_resolution_allocates_nothing :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator)
	defer mem.tracking_allocator_destroy(&track)
	context.allocator = mem.tracking_allocator(&track)

	table: rdf.Intern_Table
	rdf.intern_table_init(&table)
	defer rdf.intern_table_destroy(&table)
	scratch: Scratch
	defer scratch_destroy(&scratch)

	refs := [?]string{"g", "../g", "?y", "#s", "g/../h", "//net/x"}
	for ref in refs {
		_, ok := resolve(&table, RFC_BASE, ref, &scratch)
		testing.expect(t, ok)
	}
	first_pass := track.total_allocation_count
	for _ in 0 ..< 100 {
		for ref in refs {
			_, ok := resolve(&table, RFC_BASE, ref, &scratch)
			testing.expect(t, ok)
		}
	}
	// Repeats hit the intern table and the retained scratch capacity:
	// zero further allocations.
	testing.expectf(
		t,
		track.total_allocation_count == first_pass,
		"repeat resolutions allocated: %v -> %v",
		first_pass,
		track.total_allocation_count,
	)
}
