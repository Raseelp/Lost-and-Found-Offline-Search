# Comments

How comments are written in the Dart and Kotlin code. The code should be clear enough that most things need no
comment at all.

## Code first

Make the code say it: a clear name, a named constant, a small function. A comment is written only when the code
cannot say it. Do not split code into tiny functions just to avoid a comment. Split a function only when a part of
it needs explaining.

## What a comment says

A comment says what a class or a function does and why, and what it assumes. It does not say how the code works.
It does not repeat the name, the signature or the type.

## Where comments go

- Above a class, a function or another member, as a doc comment (`///` in Dart, `/** */` in Kotlin). Start with one
  short sentence. Carry on in plain sentences if more is needed. Refer to code with square brackets, as in
  [loopUnlessCalm].
- Not inside function bodies. When a part of a body needs explaining, it becomes its own function, and the name and
  the doc comment of that function do the explaining.
- The one exception is a short note on something really clever or ugly: a workaround for a phone, an Android version
  or a library fault, or a trap that is easy to break. It is two lines at most, and it is rare.
- A note on a field or a constant follows the same rule. It is written only for a unit, a special value or a rule
  that the name does not show, and it is one short sentence.
- A private member gets a doc comment only when its name is not enough.

## Not allowed

- Dividers and section headings, such as lines of dashes or `// ---- Name ----`. Order members logically and
  separate them with blank lines.
- Numbered steps, bullet lists, bold text, arrows, symbols and tables in comments. Write sentences.
- Commented-out code. Delete it.
- Comments about the change or the past, such as "now", "new", "used to" or "was tried first". That belongs in the
  commit message.
- Comments that repeat what the code says.
- Em dashes, emoji and marketing words.

## A past attempt

A note about something that was tried and failed stays only when removing it would let someone break the code again,
or when it explains a workaround that is not obvious. It says what breaks and why, in plain words, above the code
it protects. A longer design story goes in `docs/` instead.

## TODO

`TODO(name): what is left, and what makes it time to do it.` Never a bare TODO.

## Wording

Plain short sentences that end with a full stop. Use the names the code uses. Tests follow the same rules.

## Checking a comment-only change

The code with every comment removed must be identical to what it was before. The analyzer must report no new issues,
and the Kotlin build must pass.
