# Communication

## The target: 80% of the way to ASD-STE100

Write every piece of prose at **80% of the way to ASD-STE100 (Simplified Technical
English)**. Short sentences, common words, explicit logic, no fluff.

ASD-STE100 is a controlled-English specification published by ASD (the AeroSpace,
Security and Defence Industries Association of Europe). The European airline industry
asked for it in the 1980s so that aircraft maintenance manuals read the same way to
every mechanic on earth, whatever their first language. Issue 9 is current. It holds
**53 writing rules in 9 sections** plus a dictionary of about **900 approved words** —
each locked to one meaning and one part of speech — and about **1,200 words to avoid**
with replacements.

It works because it removes the writer's freedom to be interesting. That is also why we
take 80% and not 100%. The 80% is the structure and the logic. The 20% we drop is the
closed vocabulary, which would make real technical work impossible to discuss.

## Scope

This governs prose: chat replies, commit messages, PR bodies, code comments,
documentation, plans, status reports, error messages.

It does **not** govern, and you never rewrite:

- Code, identifiers, file paths, flags, config keys
- Quoted command output, error text, logs, test failures
- Text the user wrote, or text you are quoting back
- Commit trailers and other machine-read lines

## The 80% we adopt

### Sentences

- **One idea per sentence.** One instruction per sentence, unless two actions truly
  happen at the same time.
- **20 words maximum** for an instruction. **25 words maximum** for a description.
- **Condition first, then the command, separated by a comma.** "If the build fails, run
  `make clean`." Not "Run `make clean` if the build fails."
- **No semicolons in prose.** Use two sentences, or `and`, `but`, `then`, `so`.
- Connect sentences with plain words: `and`, `but`, `then`, `so`, `as a result`.

### Paragraphs and lists

- One topic per paragraph. **6 sentences maximum.**
- Go from general to specific, one layer at a time. Do not open on the detail.
- Use a vertical list for 3 or more parallel items or steps.
- Keep list items grammatically parallel. Do not mix steps and descriptions in one list.

### Verbs

- **Active voice.** Imperative for anything the reader must do.
- Allowed forms: infinitive, imperative, simple present, simple past, simple future, and
  the past participle used as an adjective ("the configured value" is fine, and is not
  passive).
- **Banned: present perfect, past perfect, and every progressive tense.** Write "I fixed
  the binding", not "I have fixed the binding" and not "I am fixing the binding".
- **Banned: stacked auxiliaries + past participle** — "is to be run", "can be seen",
  "must be configured", "will be deleted". Rewrite active: "run it", "you can see",
  "configure it", "it deletes".
- **Use a verb, not a noun phrase.** "to configure the cache", not "for the
  configuration of the cache". "decide", not "make a decision".
- Reserve `-ing` for genuine nouns and modifiers (`a running process`). Never for tense.

### Words

- **One term per concept, every time.** Pick `worktree` or `checkout` and never alternate
  for variety. Varying the word is how a reader concludes there are two things.
- **Compound nouns: 3 words maximum.** Longer than that, define a short form once and
  reuse it.
- **No Latin abbreviations.** Not `e.g.`, `i.e.`, `etc.`, `via`. Write `for example`,
  `that is`, `and so on`, `through`.
- **Pronouns only when the reference cannot be misread.** A sentence that opens with
  "It" or "This" almost always needs the noun instead.
- **Avoid phrasal verbs whose meaning is not the sum of the parts** — unless the phrase
  is the established name for the thing. `roll back a migration` and `check out a branch`
  stay. "The build blew up" becomes "the build failed".
- Keep the conjunction `that` after `make sure`, `show`, `recommend`. "Make sure that the
  key is free."
- Gender-neutral throughout. They/them for a person whose pronouns you do not know.

### Risk

When you flag something destructive or hard to reverse, give three things in order: the
command or change, the damage it causes, and the condition under which it happens. Never
bury an instruction inside an aside. A note informs. It never instructs.

### Fluff to delete on sight

`Great question` · `I'll go ahead and` · `Let me just` · `Basically` · `Essentially` ·
`It's worth noting that` · `In order to` (write `to`) · `At this point in time` (write
`now`) · `Please note that` · `As you can see` · `Simply` · `Just` · restating the
question before answering it.

## The 20% we drop, on purpose

- **The 900-word approved dictionary.** Domain words win. Say `idempotent`, `rebase`,
  `symlink`, `coroutine`. Never swap the real name of a command or concept for an
  approved near-synonym — STE's own rule is that a technical noun or verb beats a
  paraphrase.
- **The ban on contractions.** `don't` and `it's` are shorter and read faster. Keep them.
- **The WARNING / CAUTION block format.** That is an aerospace manual convention.
- **Hard sentence-length limits inside code comments** where the code demands more.

## Checklist

Before sending prose, check:

- [ ] First line answers the question
- [ ] No sentence over 25 words, no instruction over 20
- [ ] Active voice, allowed tenses only
- [ ] No semicolons, no Latin abbreviations, no fluff phrases
- [ ] Same term for the same concept throughout
- [ ] Every `it` and `this` has one possible referent
- [ ] Conditions stated before their commands
- [ ] Code, output and quotes left exactly as they are
