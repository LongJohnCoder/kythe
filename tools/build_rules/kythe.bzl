def extract(ctx, kindex, args, inputs=[], mnemonic=None, mkdir='.'):
  inputs, _, input_manifests = ctx.resolve_command(tools=[ctx.attr._extractor])
  cmd = '\n'.join([
      'set -e',
      'export KYTHE_ROOT_DIRECTORY="$PWD"',
      'export KYTHE_OUTPUT_DIRECTORY="$(dirname ' + kindex.path + ')"',
      'export KYTHE_VNAMES="' + ctx.file.vnames_config.path + '"',
      'mkdir -p "$KYTHE_OUTPUT_DIRECTORY"',
      'mkdir -p "' + mkdir + '"',
      ctx.executable._extractor.path + " " + ' '.join(args),
      'mv "$KYTHE_OUTPUT_DIRECTORY"/*.kindex ' + kindex.path])
  ctx.action(
      inputs = ctx.files.srcs + inputs + inputs + [ctx.file.vnames_config],
      outputs = [kindex],
      mnemonic = mnemonic,
      command = cmd,
      input_manifests = input_manifests,
      use_default_shell_env = True)

def index(ctx, kindex, entries, mnemonic=None):
  inputs, _, input_manifests = ctx.resolve_command(tools=[ctx.attr._indexer])
  cmd = "\n".join([
      "set -e",
      'CWD="$PWD"',
      "cd /tmp",
      '"$CWD"/' + ctx.executable._indexer.path + " " + " ".join(ctx.attr.indexer_opts) + ' "$CWD"/' + kindex.path + ' > "$CWD"/' + entries.path,
  ])
  ctx.action(
      inputs = [kindex] + inputs,
      outputs = [entries],
      mnemonic = mnemonic,
      command = cmd,
      input_manifests = input_manifests,
      use_default_shell_env = True)

def verify(ctx, entries):
  all_srcs = set(ctx.files.srcs)
  all_entries = set([entries])
  for dep in ctx.attr.deps:
    all_srcs += dep.sources
    all_entries += [dep.entries]

  ctx.file_action(
      output = ctx.outputs.executable,
      content = '\n'.join([
        "#!/bin/bash -e",
        "set -o pipefail",
        "cat " + " ".join(cmd_helper.template(all_entries, "%{short_path}")) + " | " +
        ctx.executable._verifier.short_path + " " + " ".join(ctx.attr.verifier_opts) +
        " " + cmd_helper.join_paths(" ", all_srcs),
      ]),
      executable = True,
  )
  return ctx.runfiles(files = list(all_srcs) + list(all_entries) + [
      ctx.outputs.executable,
      ctx.executable._verifier,
  ], collect_data = True)

def java_verifier_test_impl(ctx):
  inputs = []
  classpath = []
  for dep in ctx.attr.deps:
    inputs += [dep.jar]
    classpath += [dep.jar.path]

  jar = ctx.new_file(ctx.configuration.bin_dir, ctx.label.name + ".jar")
  srcs_out = jar.path + '.srcs'

  args = ['-encoding', 'utf-8', '-cp', "'" + ':'.join(classpath) + "'", '-d', srcs_out]
  for src in ctx.files.srcs:
    args += [src.short_path]

  ctx.action(
      inputs = ctx.files.srcs + inputs + [ctx.file._jar, ctx.file._javac] + ctx.files._jdk,
      outputs = [jar],
      mnemonic = 'MockJavac',
      command = '\n'.join([
          'set -e',
          'rm -rf ' + srcs_out,
          'mkdir ' + srcs_out,
          ctx.file._javac.path + '  ' + ' '.join(args),
          ctx.file._jar.path + ' cf ' + jar.path + ' -C ' + srcs_out + ' .',
      ]),
      use_default_shell_env = True)

  kindex = ctx.new_file(ctx.configuration.genfiles_dir, ctx.label.name + "/compilation.kindex")
  extract(ctx, kindex, args, inputs=inputs+[jar], mnemonic='JavacExtractor', mkdir=srcs_out)

  entries = ctx.new_file(ctx.configuration.bin_dir, ctx.label.name + ".entries")
  index(ctx, kindex, entries, mnemonic='JavaIndexer')

  runfiles = verify(ctx, entries)
  return struct(
      runfiles = runfiles,
      jar = jar,
      entries = entries,
      sources = ctx.files.srcs,
      files = set([kindex, entries]),
  )

def cc_verifier_test_impl(ctx):
  entries = []
  concat_entries = ctx.new_file(ctx.configuration.bin_dir, ctx.label.name + ".entries")
  concat_entries_cmd = ""

  for src in ctx.files.srcs:
    args = ['-std=c++11']
    if ctx.var['TARGET_CPU'] == 'darwin':
      # TODO(zarko): This needs to be autodetected (or does doing so even make
      # sense?)
      args += ['-I/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/include/c++/v1']
      args += ['-I/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.11.sdk/usr/include']
    args += ['-c', src.short_path]
    kindex = ctx.new_file(ctx.configuration.genfiles_dir, ctx.label.name + "/compilation/" + src.short_path + ".kindex")
    extract(ctx, kindex, args, inputs=[src], mnemonic='CcExtractor')
    entry = ctx.new_file(ctx.configuration.genfiles_dir, ctx.label.name + "/compilation/" + src.short_path + ".entries")
    entries += [entry]
    index(ctx, kindex, entry, mnemonic='CcIndexer')
    concat_entries_cmd += 'cat ' + entry.path + ' >> ' + concat_entries.path + '\n'

  ctx.action(
    inputs = ctx.files.srcs + entries,
    outputs = [concat_entries],
    mnemonic = 'ConcatEntries',
    command = concat_entries_cmd,
    use_default_shell_env = True)

  runfiles = verify(ctx, concat_entries)
  return struct(
      runfiles = runfiles,
  )

base_attrs = {
    "vnames_config": attr.label(
        default = Label("//kythe/data:vnames_config"),
        allow_files = True,
        single_file = True,
    ),
    "_verifier": attr.label(
        default = Label("//kythe/cxx/verifier"),
        executable = True,
    ),
    "indexer_opts": attr.string_list([]),
    "verifier_opts": attr.string_list(["--ignore_dups"]),
}

java_verifier_test = rule(
    java_verifier_test_impl,
    attrs = base_attrs + {
        "srcs": attr.label_list(allow_files = FileType([".java"])),
        "deps": attr.label_list(
            allow_files = False,
            providers = [
                "entries",
                "sources",
                "jar",
            ],
        ),
        "_extractor": attr.label(
            default = Label("//kythe/java/com/google/devtools/kythe/extractors/java/standalone:javac_extractor"),
            executable = True,
        ),
        "_indexer": attr.label(
            default = Label("//kythe/java/com/google/devtools/kythe/analyzers/java:indexer"),
            executable = True,
        ),
        "_javac": attr.label(
            default = Label("//tools/jdk:javac"),
            single_file = True,
        ),
        "_jar": attr.label(
            default = Label("//tools/jdk:jar"),
            single_file = True,
        ),
        "_jdk": attr.label(
            default = Label("//tools/jdk:jdk"),
            allow_files = True,
        ),
    },
    executable = True,
    test = True,
)

cc_verifier_test = rule(
    cc_verifier_test_impl,
    attrs = base_attrs + {
        "srcs": attr.label_list(allow_files = FileType([
            ".cc",
            ".h",
        ])),
        "deps": attr.label_list(
            allow_files = False,
        ),
        "_extractor": attr.label(
            default = Label("//kythe/cxx/extractor:cxx_extractor"),
            executable = True,
        ),
        "_indexer": attr.label(
            default = Label("//kythe/cxx/indexer/cxx:indexer"),
            executable = True,
        ),
        "indexer_opts": attr.string_list(["-ignore_unimplemented"]),
    },
    executable = True,
    test = True,
)
