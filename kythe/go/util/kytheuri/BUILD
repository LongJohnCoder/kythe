load("//tools:build_rules/shims.bzl", "go_test")
load("@io_bazel_rules_go//go:def.bzl", "go_library")

# N.B. This package is given proto visibility although it is not a proto,
# because it is impractical to use the Kythe protos without ticket support.
package(default_visibility = ["//kythe:proto_visibility"])

go_library(
    name = "kytheuri",
    srcs = [
        "escape.go",
        ":uri.go",
    ],
    deps = ["//kythe/proto:storage_go_proto"],
)

go_test(
    name = "kytheuri_test",
    size = "small",
    srcs = [
        "bench_test.go",
        "uri_test.go",
    ],
    library = "kytheuri",
    visibility = ["//visibility:private"],
    deps = [
        "//kythe/proto:storage_go_proto",
        "@go_protobuf//:proto",
    ],
)
