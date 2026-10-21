---
name: sync-jdk-env
description: Reconcile the JDK<major> exports in ~/.zshenv with the JDKs asdf actually has installed, after an asdf java version bump or a fresh install. Use when a Gradle build fails with "Cannot find a Java installation on your machine ... matching {languageVersion=N}", when JDK8/JDK17/JDK21 and friends point at directories that no longer exist, or after `asdf install java <version>` changes which build a major resolves to.
---

# Sync the JDK toolchain exports

## Why these variables exist

The Develocity monorepo's `gradle.properties` turns off toolchain discovery and relies on the environment instead:

```properties
org.gradle.java.installations.auto-detect=false
org.gradle.java.installations.auto-download=false
org.gradle.java.installations.fromEnv=JDK7,JDK8,JDK11,JDK17,JDK21,JDK25
```

So Gradle finds a JDK only through `JDK<major>`. Modules pinned to an older release need one: `nullability-lib-common` sets `javaVersion.set(VERSION_1_8)`, so a build touching it wants `JDK8` whatever the daemon runs on.

The failure is not obvious from its message:

```
Cannot find a Java installation on your machine (Mac OS X ...) matching:
{languageVersion=8, vendor=any vendor, ...}. Toolchain auto-provisioning is not enabled.
```

Since Gradle 9.7.1 this surfaces while saving the configuration cache, so it fails the whole build rather than only the tasks that needed the toolchain.

## Why they live in ~/.zshenv

`~/.macstrap/configs/dotfiles/.exports` sets them too, but that file is sourced from `.zshrc`, which only interactive shells read. Anything scripted — agent tool calls, tmux panes started by launchd, CI-ish local runs — gets a shell without them and fails at configuration time. `.zshenv` is read by every zsh, so the variables are there whatever started the process.

Paths are written literally rather than through `asdf where`, which is not on `PATH` that early, and which would otherwise cost a subprocess per JDK on every shell start. Literal paths are what needs maintaining, and this skill is that maintenance.

## Running it

```bash
~/.claude/skills/sync-jdk-env/sync-jdk-exports.sh --check   # report drift, exit 1 if any
~/.claude/skills/sync-jdk-env/sync-jdk-exports.sh           # rewrite, after taking a backup
```

It reports three things:

- **stale** — the export points somewhere that is not the newest install for that major. Rewritten.
- **orphan** — a major is exported but nothing is installed for it. Reported only: deleting an export is a decision about whether that toolchain is still wanted, so it is left alone.
- **not exported** — an LTS major is installed but has no export. Reported only, since adding one is a judgement about whether a build wants it. Non-LTS releases are ignored: a build is not going to pin to one for long.

Only majors already exported are rewritten, so it will not invent variables.

## After running it

Existing shells keep the old values, including the tmux server that aoe sessions attach to. Open a new shell, or restart the aoe daemon, before expecting a build to see the change.

## Configuration

Environment overrides, all optional:

- `ZSHENV` — file to reconcile, default `~/.zshenv`
- `ASDF_JAVA_INSTALLS` — where to look, default `~/.asdf/installs/java`
- `JDK_VENDOR_PREFIX` — install prefix to consider, default `liberica`, so a GraalVM install alongside is left out
- `JDK_LTS_MAJORS` — which majors are worth flagging when unexported, default `8 11 17 21 25`

## Checking the result

`zsh -c 'env | grep ^JDK'` uses neither `.zshrc` nor a login shell, so it shows what a scripted process will actually see. That is the case that breaks; an interactive shell will look fine either way because `.exports` sets the same variables again.
