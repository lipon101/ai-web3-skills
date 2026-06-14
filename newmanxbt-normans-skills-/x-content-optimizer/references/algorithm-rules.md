# X Algorithm Optimization Reference

Based on X's open-source recommendation system (Phoenix + Home Mixer).

## Scoring System Overview

X uses a Grok-based transformer (Phoenix) to predict engagement:

```
Final Score = Σ (weight × P(action)) + offset_adjustment
```

Content ranked by **predicted engagement**, not chronological order.

---

## Positive Engagement Signals

| Signal | What It Measures | Optimization |
|--------|------------------|--------------|
| **Favorite** | P(like) | Emotional resonance, valuable insight |
| **Reply** | P(reply) | Questions, discussion hooks |
| **Retweet** | P(repost) | Share-worthy, quotable content |
| **Quote** | P(quote tweet) | Hot takes worth commenting on |
| **Share** | P(share) | "Send to someone" content |
| **Share via DM** | P(DM share) | Personal relevance |
| **Share via Copy Link** | P(copy link) | Reference-worthy |
| **Click** | P(expand tweet) | Curiosity-inducing hooks |
| **Profile Click** | P(visit profile) | Expertise signals |
| **Photo Expand** | P(expand image) | Intriguing visuals |
| **Video Quality View** | P(quality view)* | Engaging video content |
| **Dwell** | P(dwell on tweet) | Engaging content |
| **Dwell Time** | Predicted time spent | Depth of content |
| **Follow Author** | P(follow) | Consistent value |

*VQV only for videos exceeding minimum duration

---

## Negative Signals (Penalties)

| Signal | Trigger | Impact |
|--------|---------|--------|
| **Not Interested** | Irrelevant content | Negative weight |
| **Block Author** | Harassment/spam | Severe penalty |
| **Mute Author** | Annoying/excessive | Moderate penalty |
| **Report** | Policy violations | Severe penalty |

---

## Learned Penalties (Indirect)

These aren't explicit in code but learned by the ML model:

| Factor | Why It Hurts | Mechanism |
|--------|--------------|-----------|
| **External Links** | Takes users OFF platform | Lower dwell_time, fewer subsequent engagements |
| **Link-only tweets** | No native content value | Low dwell, users leave immediately |
| **Clickbait without payoff** | Users bounce quickly | Low dwell_time, possible "not interested" |

**External Links Impact:**
- No `ClientExternalLinkClick` as positive signal
- Users clicking external links = leaving X = lower dwell
- Model learns: external links → lower engagement prediction
- **Mitigation**: Provide value IN the tweet, link as supplement

---

## Special Scoring Factors

### Author Diversity Decay
Repeated posts from same author get progressively reduced scores.

### In-Network Boost
Posts from followed accounts > out-of-network discovery.

### Video Quality View
Only for videos exceeding minimum duration threshold.

---

## Single Tweet Optimization

### Structure
```
[Hook] - First 50 chars visible in preview
[Core Value] - Main insight delivered IN tweet
[Engagement Driver] - Question or CTA
```

### Priority Signals
1. **Favorite/Like** - Emotional or valuable
2. **Reply** - Discussion-worthy
3. **Retweet** - Share-worthy
4. **Dwell** - Holds attention

### External Link Strategy
- Deliver core value IN the tweet
- Link as optional "learn more"
- Never make link the only value
- Consider: screenshot + context > raw link

---

## X Article Optimization

### Why Articles Win Over Links
- Content stays ON platform (dwell time)
- Native format = algorithm friendly
- Full engagement tracking possible

### Structure
```
[Title] - Curiosity + value promise
[Preview] - Expands on value
[Body] - Structured, valuable sections
[Closing] - Summary + CTA
```

---

## Thread Optimization

### Position Strategy
| Position | Focus | Signal Target |
|----------|-------|---------------|
| Tweet 1 | Hook | Click, Dwell |
| Tweet 2-3 | Engage | Reply |
| Middle | Value | Dwell Time |
| Final | CTA | Repost, Follow |

---

## Audit Checklist

### Positive Signal Check
- [ ] Like potential: Emotionally resonant?
- [ ] Reply potential: Discussion-worthy?
- [ ] Repost potential: Share-worthy?
- [ ] Dwell potential: Holds attention?

### Negative Signal Risk
- [ ] Not Interested: Relevant to audience?
- [ ] Mute risk: Frequency reasonable?
- [ ] Block risk: Respectful content?
- [ ] Report risk: Policy compliant?

### External Link Check
- [ ] Core value delivered IN tweet?
- [ ] Link supplementary, not essential?
- [ ] Consider native alternative (article, screenshot)?
- [ ] If link required: context + value before link?

### Format Check
- [ ] Content complete and polished
- [ ] Key information emphasized
- [ ] Readable formatting
- [ ] No unnecessary padding
