load("//tools:build_rules/shims.bzl", "go_test")
load("@io_bazel_rules_go//go:def.bzl", "go_library")

package(default_visibility = ["//kythe:default_visibility"])

go_library(
    name = "edges",
    srcs = ["edges.go"],
    deps = ["//kythe/go/util/schema"],
)

go_test(
    name = "edges_test",
    size = "small",
    srcs = ["edges_test.go"],
    library = "edges",
    visibility = ["//visibility:private"],
    deps = ["//kythe/go/test/testutil"],
)
