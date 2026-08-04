# Where these came from

These three documents were carried over from the full
[Chronie](https://github.com/dipasqualew/chronie) unchanged except for file paths, because
comments throughout `chronie/src` point at them by name: they are the reasoning behind
decisions the code only states the conclusion of.

They describe **both** halves of Chronie, and Lite is only one of them. So where a paragraph
names something under `apps/desktop/` — a Rust collector, a React view, a fixture — it is
describing the desktop app, which is not in this repository and which nothing here talks to.
Read those as background on why the addon writes what it writes, not as an account of what
this build does.

The one that matters most for Lite is [`account-census.md`](account-census.md). It is the
argument for the walk that this build ships switched off, and it is worth reading before
turning `sync.census` on — it says what the walk costs, what it is for, and what it can and
cannot tell you.
