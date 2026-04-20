# sardine-track — the story

## Why This Exists

It's easy to gaslight yourself into thinking you're having panic attacks and are lazy. And sometimes people have panic attacks and are lazy, and that's entirely normal.

But when the shortness of breath is uncoupled from emotion, when the "laziness" is less sloth and more that you're stuck in a quagmire of quicksand despite wanting to do *so much* -- there's something making your body react that way.

The sun was making me sick.

At least that was my intuition, but that seemed insane. I had low vitamin D for years and was told to get more sun. But like clockwork, high UV index days would leave me sick the next day, or two, or three. A sunburn put me in bed for a week with what felt like the flu.

I figured I was just getting older. Also I'm hella pale, maybe this was a white people thing no one had mentioned to me.

But coupled with a family history sprinkled with, and a genetic profile loaded for, SARDs and connective tissue disease associated alleles -- I decided to quantify it. It became painfully clear to me by the data, that unfortunately, The sun is making me sick.

That's why I started a spreadsheet. But it was useless in clinic -- rows upon rows of entries with no succinct way to visually communicate what they meant in a 15-minute appointment, while exhausted and in pain and anxious about being dismissed again. After 90+ days I gave up. I got depressed. I kept getting sick. My sick leave was running dry at work, and with out a diagnosis I didn't feel confident that I could get FMLA protection.

Then I picked it back up. I can't remember exactly what the impetus was -- probably another rheumatologist doubting me while ER doctors were writing "I believe her condition to be rheumatic in nature", meanwhile my dermatologist was doing her damnedest to get the best biopsy shave for DIF this side of the Mississippi. Damn near the size of a mercury dime.

Claude Sonnet helped me build it. I'm not a strong coder -- I can get around, and I know how to make infinity while loops, but I'm far from skilled. The LLM assisted me in building the stack, troubleshooting bugs, and providing the kind of cognitive support I could direct, debug, and reiterate. And if Claude can be annoyed, I most certainly annoyed that poor tireless machine.

Meanwhile, I was in and out of doctors appointments and a few ER visits, and eventually arrived at a shiny new "cool, I was right" / "fuck, why do I have to be right about this?" diagnosis. Eight months from when I started aggressively seeking treatment to confirmed diagnosis. I beat the odds -- the average diagnostic delay is four to seven years. I'm lucky. A lot of people aren't.

My current diagnosis is acute cutaneous lupus erythematosus with systemic involvement, confirmed by biopsy and with woefully unremarkable serology. But autoimmune disease evolves, & we are constantly learning new things about the human body. The differential will shift. The ICD codes may change. Whether we end up calling it lupus or the Hokey Pokey Disease, getting that process *started* -- having longitudinal evidence, having dates, having correlations -- matters enormously for health outcomes down the road.

This tool isn't a lupus tracker, necessarily, though it is designed around an evolving case of predictably photosensitive lupus. It's a *you* tracker, the intent is you can change it to fit your case. Whatever you've got going on.

---

## Philosophy

**Patients are the experts on their own bodies.** You know when something is wrong, even when tests are "normal." You also probably, for the most part, know the difference between normal and "oh no this is no good now." Trust that instinct.

**Correlation is worth investigating, even when causation isn't proven.** If UV exposure consistently precedes your symptoms, that pattern matters -- regardless of whether a doctor believes you yet. Or hell, you don't believe you yet.

**Your data is yours.** No surveillance, no selling, no cloud lock-in. You can delete everything and walk away at any time.

**Invisible illness deserves visible evidence.** When your symptoms are dismissed as anxiety or "borderline," a longitudinal graph can shift the conversation.

**Diagnostic complexity is real.** Some conditions take years to name. The average diagnostic delay for lupus alone is four to seven years, and it isn't even a particularly rare disease, merely uncommon. Tools like this exist to help you survive that journey and shorten it where and when possible.

---

## Acknowledgments

Built by C. Alaric Moore, a USPS electronics technician and mechanic and patient who got tired of being told her labs were normal.

Assisted by Claude (Anthropic) across multiple model generations and roles. Sonnet handled the original build. Opus (nicknamed Clode) led the forecasting-model work, data analysis pipeline, and the `/interventions` rebuild. A second Claude instance (Wolf) handles statistical validation and clinical-literature cross-checking for features that could otherwise drift into confirmation bias. A third instance (Claude-Work) covers brainstorming. H/t to GitHub Copilot for closing parentheses and other surprisingly convenient features.

The app's model explainer and much of this README were written collaboratively — where the voice is right, it's because a tireless language model internalized the tone after many, many iterations.

Inspired by every patient who was told "your labs are fine" when they knew something was deeply wrong. Dedicated to the ones still waiting for someone to believe them.

Also inspired by the rheumatologist who fired me for being right about a lab interpretation. I might be sick, but I'm still a stubborn Okie.
