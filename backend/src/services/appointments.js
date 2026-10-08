const Appointment = require('../models/Appointment');
const { isValidId } = require('../middleware/validate');
const { notFound } = require('../utils/errors');
const T = require('../utils/time');

const STATUS_META = {
  pending: { label: 'Pending', tone: 'amber' },
  confirmed: { label: 'Confirmed', tone: 'green' },
  reschedule_requested: { label: 'Reschedule requested', tone: 'blue' },
  reschedule_proposed: { label: 'New time proposed', tone: 'blue' },
  declined: { label: 'Declined', tone: 'red' },
  cancelled: { label: 'Cancelled', tone: 'red' },
  completed: { label: 'Completed', tone: 'grey' },
  no_show: { label: 'Missed', tone: 'grey' },
};

const personLite = (u) => (u && u._id ? {
  id: u._id.toString(),
  name: u.name,
  initials: u.initials,
  photoUrl: u.photoUrl || undefined,
  title: u.professional?.title,
  studentId: u.studentId,
  faculty: u.faculty,
  year: u.year,
} : null);

// What a counsellor sees instead of the student on an anonymous booking. No id, so nothing can
// be looked up or linked to the student's other bookings.
const anonymousStudent = () => ({ id: null, name: 'Anonymous student', initials: 'AS', anonymous: true });

// Name to use in notifications and reminders sent to the counsellor.
const studentName = (a, fallback) => (a.anonymous ? 'An anonymous student' : (a.student?.name || fallback || 'A student'));

// The same four-step timeline is shown to the student and the counsellor (FR4, NFR5).
function timeline(a, viewer) {
  const find = (s) => (a.history || []).find((h) => h.status === s);
  const created = find('pending');
  const when = (d) => (d ? `${T.fmtDateTime(d)}` : '');
  const sessionStep = { label: 'Session', sub: T.fmtDateTime(a.start), s: a.status === 'completed' ? 'done' : 'todo' };
  const steps = [{ label: 'Request sent', sub: when(created?.at || a.createdAt), s: 'done' }];
  switch (a.status) {
    case 'pending':
      steps.push({ label: viewer === 'counsellor' ? 'Your review' : 'Counsellor review', sub: 'Usually within 24 hours', s: 'now' });
      steps.push({ label: 'Confirmed', sub: 'Reminders 24 h and 1 h before', s: 'todo' }, sessionStep);
      break;
    case 'declined':
      steps.push({ label: 'Declined', sub: a.decline?.reason || '', s: 'bad' });
      break;
    case 'cancelled':
      steps.push({ label: 'Cancelled', sub: when(a.cancel?.at), s: 'bad' });
      break;
    case 'reschedule_requested':
    case 'reschedule_proposed': {
      const conf = find('confirmed');
      steps.push({ label: 'Confirmed', sub: when(conf?.at), s: 'done' });
      steps.push({
        label: a.status === 'reschedule_requested' ? 'Reschedule requested' : 'New time proposed',
        sub: a.proposal?.start ? `New time: ${T.fmtDateTime(a.proposal.start)}` : '',
        s: 'now',
      });
      steps.push(sessionStep);
      break;
    }
    default: {
      const conf = find('confirmed');
      steps.push({ label: 'Confirmed', sub: when(conf?.at), s: 'done' });
      steps.push({ label: 'Reminders', sub: '24 h and 1 h before', s: a.status === 'confirmed' ? 'now' : 'done' });
      steps.push(a.status === 'no_show' ? { ...sessionStep, s: 'bad', sub: 'Missed' } : sessionStep);
    }
  }
  return steps;
}

function serialize(a, viewer) {
  const meta = STATUS_META[a.status] || { label: a.status, tone: 'grey' };
  const o = {
    id: a._id.toString(),
    reference: a.reference,
    start: a.start,
    end: a.end,
    mode: a.mode,
    anonymous: !!a.anonymous,
    location: a.location,
    meetingLink: a.status === 'confirmed' || a.status === 'reschedule_requested' || a.status === 'reschedule_proposed' ? a.meetingLink : undefined,
    status: a.status,
    statusLabel: meta.label,
    statusTone: meta.tone,
    isActive: ['pending', 'confirmed', 'reschedule_requested', 'reschedule_proposed'].includes(a.status),
    hasNote: !!a.note,
    proposal: a.proposal?.start ? { start: a.proposal.start, end: a.proposal.end, reason: a.proposal.reason, by: a.proposal.by } : null,
    decline: a.decline?.reason ? { reason: a.decline.reason, message: a.decline.message, suggestedSlots: a.decline.suggestedSlots || [] } : null,
    cancel: a.cancel?.at ? { reason: a.cancel.reason, by: a.cancel.by, at: a.cancel.at } : null,
    remindersOn: a.remindersOn,
    session: a.session?.startedAt ? a.session : null,
    duplicateFlag: (a.duplicateOf || []).length > 0 && a.status === 'pending',
    createdAt: a.createdAt,
    timeline: timeline(a, viewer),
  };
  // The booking note is shared only between the student who wrote it and their counsellor.
  if (viewer === 'student' || viewer === 'counsellor') o.note = a.note || '';
  if (a.student) o.student = a.anonymous && viewer !== 'student' ? anonymousStudent() : personLite(a.student);
  if (a.counsellor) o.counsellor = personLite(a.counsellor);
  return o;
}

// ---------- Shared by the appointment and counselling-session modules ----------
const POP = [
  { path: 'student', select: 'name studentId faculty year role notificationPrefs' },
  { path: 'counsellor', select: 'name professional role notificationPrefs photo' },
];

// Loads an appointment the signed-in student or counsellor is part of; anyone else gets 404.
async function loadFor(req, id) {
  if (!isValidId(id)) throw notFound('Appointment not found.');
  const a = await Appointment.findById(id).populate(POP);
  if (!a) throw notFound('Appointment not found.');
  const me = req.user._id.toString();
  if (a.student._id.toString() !== me && a.counsellor._id.toString() !== me) throw notFound('Appointment not found.');
  return a;
}

// Serializes for whoever is asking (student or counsellor view).
const outFor = (req, a) => serialize(a, req.user.role);

module.exports = { serialize, timeline, STATUS_META, personLite, anonymousStudent, studentName, POP, loadFor, outFor };
