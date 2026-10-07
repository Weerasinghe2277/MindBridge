// Bridge — the AI wellness assistant (FR10). It is supportive, never clinical,
// and hands off to the 1926 helpline when a message suggests risk (FR8).
const Anthropic = require('@anthropic-ai/sdk');
const env = require('../config/env');

const client = env.anthropicKey ? new Anthropic({ apiKey: env.anthropicKey }) : null;

// Server-side safety net. Matching messages never go to the model: the student is
// shown crisis support immediately.
const CRISIS = /(suicid|kill (my ?self|myself)|end (it all|my life)|hurt (my ?self|myself)|self[\s-]?harm|cut(ting)? myself|want to die|wanna die|(don'?t|do not) want to (live|be here|be alive)|can'?t go on|cannot go on|can'?t keep going|no reason to live|better off dead|overdose)/i;

// Phone keyboards insert curly apostrophes (don’t), so normalise before matching.
const normalise = (text) => String(text).replace(/[‘’‛`´]/g, "'").replace(/\s+/g, ' ');
const isCrisis = (text) => CRISIS.test(normalise(text));

const CRISIS_REPLY = 'I’m really glad you told me. You deserve support from a real person right now, and you don’t have to wait. Please call 1926, the National Mental Health Helpline. It’s free, confidential and open 24 hours.';

const FALLBACKS = [
  'That sounds like a lot to carry. Would a 2-minute breathing exercise help right now, or would you like to talk it through a little more?',
  'Thank you for telling me. Which part of this week feels heaviest at the moment?',
  'It makes sense to feel that way. If it keeps building up, a session with a university counsellor can really help. You can see open times under Find a counsellor.',
  'You’re doing the right thing by noticing how you feel. What’s one small thing that might make the next hour a little easier?',
];

const systemPrompt = (firstName) => `You are Bridge, a supportive wellness assistant inside MindBridge, a university counselling app used by students in Sri Lanka. The student's first name is ${firstName}.

How to respond:
- Reply warmly in 1–3 short sentences of plain text. No lists, headings or markdown.
- Listen, reflect what you hear, and help the student sort their thoughts.
- Where it fits, suggest one concrete next step inside the app: a short breathing exercise, a wellness article, a calming game, or booking a university counsellor.
- You are not a therapist or doctor. Never diagnose, never give medical or medication advice, and say so kindly if asked.
- If the student mentions crisis, self-harm, suicide or being in danger, tell them to call 1926 (National Mental Health Helpline, free, 24/7) right away.
- Keep the conversation private and student-led; don't ask for identifying details.`;

function toMessages(history, text) {
  const msgs = [];
  for (const m of history) {
    const role = m.from === 'me' ? 'user' : 'assistant';
    if (!msgs.length && role === 'assistant') continue; // must start with a user turn
    const last = msgs[msgs.length - 1];
    if (last && last.role === role) last.content += `\n${m.text}`;
    else msgs.push({ role, content: m.text });
  }
  const last = msgs[msgs.length - 1];
  if (last && last.role === 'user') last.content += `\n${text}`;
  else msgs.push({ role: 'user', content: text });
  return msgs;
}

async function reply({ firstName, history, text }) {
  if (!client) return { text: FALLBACKS[history.length % FALLBACKS.length], source: 'offline' };
  try {
    const response = await client.beta.messages.create({
      model: env.bridgeModel,
      max_tokens: 4000,
      betas: ['server-side-fallback-2026-07-01'],
      fallbacks: 'default',
      output_config: { effort: 'low' },
      system: systemPrompt(firstName),
      messages: toMessages(history.slice(-12), text),
    });
    if (response.stop_reason === 'refusal') {
      return { text: FALLBACKS[2], source: 'refusal' };
    }
    const out = response.content.filter((b) => b.type === 'text').map((b) => b.text).join(' ').trim();
    return { text: out || FALLBACKS[0], source: 'claude' };
  } catch (err) {
    if (err instanceof Anthropic.RateLimitError) console.warn('[bridge] rate limited');
    else if (err instanceof Anthropic.APIError) console.warn(`[bridge] API error ${err.status}: ${err.message}`);
    else console.warn('[bridge] request failed:', err.message);
    return { text: FALLBACKS[history.length % FALLBACKS.length], source: 'offline' };
  }
}

module.exports = { reply, isCrisis, CRISIS_REPLY, enabled: () => !!client };
