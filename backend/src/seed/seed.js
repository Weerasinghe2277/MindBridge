/* eslint-disable no-await-in-loop */
// Demo data matching the MindBridge design. All dates are relative to today so
// the app always has upcoming sessions, pending requests and recent history.
// Every demo account uses the password "password123".
const crypto = require('crypto');
const mongoose = require('mongoose');
const PDFDocument = require('pdfkit');
const { saveFile } = require('../services/storage');
const User = require('../models/User');
const Appointment = require('../models/Appointment');
const M = require('../models');
const T = require('../utils/time');
const { resetCache } = require('../services/settings');
const ARTICLES = require('./articles');

const PASSWORD = 'password123';
let rng = 42;
const rand = () => { rng = (rng * 1103515245 + 12345) % 2147483648; return rng / 2147483648; };
const pick = (arr) => arr[Math.floor(rand() * arr.length)];

const today = () => T.todayStr();
const at = (dateStr, time) => T.fromLocal(dateStr, time);
const plusMin = (d, m) => new Date(d.getTime() + m * 60000);
// nth weekday (Mon–Fri) after today, n >= 1
function workday(n) {
  let d = today(); let c = 0;
  while (c < n) { d = T.addDays(d, 1); if (T.weekdayOf(d) <= 5) c += 1; }
  return d;
}
function pastWorkday(n) {
  let d = today(); let c = 0;
  while (c < n) { d = T.addDays(d, -1); if (T.weekdayOf(d) <= 5) c += 1; }
  return d;
}
// Next half-hour boundary at least `minAhead` minutes from now.
function soon(minAhead) {
  const t = Date.now() + minAhead * 60000;
  return new Date(Math.ceil(t / (30 * 60000)) * 30 * 60000);
}

async function setCreated(model, id, date) {
  await model.collection.updateOne({ _id: id }, { $set: { createdAt: date, updatedAt: date } });
}

async function writeSamplePdf(title, owner) {
  const doc = new PDFDocument({ size: 'A4', margin: 60 });
  const chunks = [];
  doc.on('data', (c) => chunks.push(c));
  const done = new Promise((resolve) => doc.on('end', resolve));
  doc.fontSize(22).fillColor('#2F5A3D').text(title);
  doc.moveDown().fontSize(12).fillColor('#22261F').text(`Issued to: ${owner}`);
  doc.moveDown().fillColor('#6E6A5D').text('SAMPLE DOCUMENT — generated for the MindBridge demo. Not a real credential.');
  doc.end();
  await done;
  const buffer = Buffer.concat(chunks);
  const id = await saveFile(buffer, `${title}.pdf`, 'application/pdf');
  return { fileName: `${title}.pdf`, storedName: id, mimeType: 'application/pdf', size: buffer.length };
}

async function mkUser(data) {
  const u = new User({ emailVerified: true, ...data });
  await u.setPassword(PASSWORD);
  await u.save();
  return u;
}

const AV = (o = {}) => ({
  workingDays: [1, 2, 3, 4, 5], startTime: '09:00', endTime: '16:30',
  lunchBreak: { enabled: true, start: '12:30', end: '13:30' }, sessionLength: 30, bufferMinutes: 0, blocks: [], ...o,
});
const approved = (since) => ({ status: 'approved', submittedAt: since, reviewedAt: since, history: [{ label: 'Application submitted', at: since }, { label: 'Approved by Student Affairs', at: since }] });

async function seed({ quiet = false } = {}) {
  const log = (...a) => { if (!quiet) console.log(...a); };
  const collections = await mongoose.connection.db.listCollections().toArray();
  for (const c of collections) await mongoose.connection.db.dropCollection(c.name);
  await Promise.all([User, Appointment, ...Object.values(M)].map((m) => m.syncIndexes()));
  resetCache();

  const jan = new Date(Date.UTC(2026, 0, 12));

  // ---------- Staff ----------
  const admin = await mkUser({ role: 'admin', name: 'Malsha Gunawardena', email: 'malsha.g@sliit.lk', phone: '+94 11 754 2104', professional: { title: 'Administrator', office: 'Student Affairs · Block A', extension: '2104' } });

  const hasini = await mkUser({
    role: 'counsellor', name: 'Dr. Hasini Kalupahana', email: 'hasini.k@sliit.lk', gender: 'female', phone: '+94 77 555 0101',
    professional: { title: 'Clinical Psychologist', qualifications: 'MSc Clinical Psychology, University of Colombo', experienceYears: 9, about: 'I work with students on exam stress, anxiety and adjusting to university life. Sessions are confidential and we go at your pace.', focusAreas: ['Stress', 'Anxiety', 'Exam pressure', 'Sleep', 'First-year adjustment'], languages: ['English', 'Sinhala'], registrationNo: 'SLPA · PS-0418', renewalDue: 'Jan 2027', modes: ['online', 'in_person'], room: 'Wellbeing Centre, Room 2.14, Main Building' },
    availability: AV({ blocks: [{ date: workday(3), from: '09:00', to: '10:00', reason: 'Faculty meeting' }, { date: workday(6), allDay: true, from: '00:00', to: '23:59', reason: 'Training' }] }),
    verification: approved(jan),
  });
  const nadeesha = await mkUser({
    role: 'counsellor', name: 'Ms. Nadeesha Fernando', email: 'nadeesha.f@sliit.lk', gender: 'female',
    professional: { title: 'Counsellor', qualifications: 'BSc Psychology, MA Counselling', experienceYears: 6, about: 'I help students manage academic pressure, time and motivation, and find a study rhythm that leaves room for rest.', focusAreas: ['Academic pressure', 'Stress', 'Sleep', 'Motivation'], languages: ['English', 'Sinhala'], registrationNo: 'SLNCC 1874', modes: ['online', 'in_person'], room: 'Wellbeing Centre, Room 2.10' },
    availability: AV({ startTime: '09:00', endTime: '15:00' }), verification: approved(jan),
  });
  const kavindu = await mkUser({
    role: 'counsellor', name: 'Mr. Kavindu Jayasinghe', email: 'kavindu.j@sliit.lk', gender: 'male',
    professional: { title: 'Counsellor', qualifications: 'BA Sociology, Diploma in Counselling', experienceYears: 4, about: 'I support students with relationships, homesickness and settling into university life, especially in first year.', focusAreas: ['Relationships', 'Homesickness', 'First-year adjustment', 'Low mood'], languages: ['English', 'Sinhala', 'Tamil'], registrationNo: 'SLNCC 2045', modes: ['online'], room: '' },
    availability: AV({ workingDays: [1, 3, 4, 5], startTime: '10:00', endTime: '16:00' }), verification: approved(jan),
  });
  const shalini = await mkUser({
    role: 'counsellor', name: 'Dr. Shalini Rajapakse', email: 'shalini.r@sliit.lk', gender: 'female',
    professional: { title: 'Counselling Psychologist', qualifications: 'PhD Counselling Psychology', experienceYears: 12, about: 'My focus is sleep, low mood and building small daily habits that make study weeks feel more manageable.', focusAreas: ['Sleep', 'Low mood', 'Anxiety', 'Mindfulness'], languages: ['English', 'Tamil'], registrationNo: 'SLPA · PS-0233', modes: ['online', 'in_person'], room: 'Wellbeing Centre, Room 2.16' },
    availability: AV({ workingDays: [2, 4], startTime: '13:00', endTime: '17:00', lunchBreak: { enabled: false, start: '12:30', end: '13:30' } }), verification: approved(jan),
  });
  const counsellors = [hasini, nadeesha, kavindu, shalini];

  const ruwan = await mkUser({
    role: 'doctor', name: 'Dr. Ruwan Dissanayake', email: 'ruwan.d@sliit.lk', gender: 'male',
    professional: { title: 'Medical Officer', qualifications: 'MBBS (Colombo)', registrationNo: 'SLMC 24518', room: 'Medical Centre · Room 4', office: 'University Medical Centre' },
    availability: AV({ startTime: '08:00', endTime: '16:30' }), verification: approved(jan),
  });

  // Applications waiting for Student Affairs
  const pendingStaff = [
    ['counsellor', 'Tharushi Wijesekara', 'tharushi.w@sliit.lk', 'Counsellor', 'MSc Counselling Psychology', 'SLNCC 2219', 4, 'pending', 2],
    ['counsellor', 'Mihiri Abeysekera', 'mihiri.a@sliit.lk', 'Counsellor', 'BSc Psychology, Diploma in Counselling', 'SLNCC 2290', 2, 'pending', 3],
    ['counsellor', 'Chamara Bandara', 'chamara.b@sliit.lk', 'Counsellor', 'MA Counselling', 'SLNCC 1960', 7, 'changes_requested', 6],
    ['doctor', 'Dr. Nirmala Karunaratne', 'nirmala.k@sliit.lk', 'Medical Officer', 'MBBS (Colombo)', 'SLMC 31207', 5, 'pending', 1],
    ['doctor', 'Dr. Sahan Peiris', 'sahan.p@sliit.lk', 'Visiting Psychiatrist', 'MBBS, MD Psychiatry', 'SLMC 19876', 11, 'pending', 4],
  ];
  for (const [role, name, email, title, qual, reg, exp, status, daysAgo] of pendingStaff) {
    const since = at(T.addDays(today(), -daysAgo), '09:12');
    const docs = role === 'doctor'
      ? [['SLMC certificate', name], ['National ID', name]]
      : [['Degree certificate', name], ['Registration certificate', name], ['National ID', name]];
    const u = await mkUser({
      role, name, email, professional: { title, qualifications: qual, registrationNo: reg, experienceYears: exp, languages: ['English'], modes: ['online', 'in_person'] },
      availability: AV(),
      verification: {
        status, submittedAt: since,
        note: status === 'changes_requested' ? 'The registration scan is blurry. Please upload a clearer copy.' : undefined,
        requestedItems: status === 'changes_requested' ? ['Registration certificate'] : [],
        documents: await Promise.all(docs.map(async ([label]) => ({ label, ...(await writeSamplePdf(label, name)) }))),
        history: [{ label: 'Application submitted', at: since }, { label: 'Documents uploaded', at: since }],
      },
    });
    await setCreated(User, u._id, since);
  }

  // ---------- Students ----------
  const S = async (name, studentId, faculty, year, extra = {}) => mkUser({ role: 'student', name, email: `${studentId.toLowerCase()}@my.sliit.lk`, studentId, faculty, year, ...extra });
  const pasindi = await S('Pasindi Perera', 'IT23714052', 'Faculty of Computing', 3, { preferredName: 'Pasindi', phone: '+94 77 123 4567', gender: 'female', privacy: { shareMoodTrends: false, biometricUnlock: true, hidePreviews: true } });
  const dinithi = await S('Dinithi Senanayake', 'IT22104587', 'Faculty of Computing', 4, { phone: '+94 71 220 9910', privacy: { shareMoodTrends: true, hidePreviews: true } });
  const ravindu = await S('Ravindu Fonseka', 'BM23001245', 'Faculty of Business', 2);
  const kasun = await S('Kasun Wijeratne', 'IT22510933', 'Faculty of Computing', 4, { phone: '+94 76 410 2283' });
  const ishara = await S('Ishara Madushani', 'EN23045671', 'Faculty of Engineering', 2);
  const tharindu = await S('Tharindu Samarasinghe', 'IT23004418', 'Faculty of Computing', 3, { phone: '+94 70 300 1189' });
  const amaya = await S('Amaya Nanayakkara', 'HS24007731', 'Faculty of Humanities & Sciences', 1, { phone: '+94 77 909 4410' });
  const named = [pasindi, dinithi, ravindu, kasun, ishara, tharindu, amaya];

  const FIRST = ['Nimal', 'Sachini', 'Hiruni', 'Dulaj', 'Kaveesha', 'Malith', 'Sanduni', 'Yasiru', 'Tharaka', 'Nethmi', 'Chamodi', 'Isuru', 'Shehan', 'Dilini', 'Lahiru', 'Rashmi', 'Pavithra', 'Janith', 'Oshadi', 'Thisara', 'Kavindi', 'Ashen', 'Nadun', 'Ruvini', 'Senuri', 'Gihan', 'Hasara', 'Vihanga', 'Anjali', 'Ramesh'];
  const LAST = ['Silva', 'Perera', 'Fernando', 'Jayawardena', 'Rathnayake', 'Bandara', 'Kumara', 'Wickramasinghe', 'Herath', 'Dissanayake', 'Gunasekara', 'Ranasinghe'];
  const FAC = [['Faculty of Computing', 'IT'], ['Faculty of Computing', 'IT'], ['Faculty of Business', 'BM'], ['Faculty of Engineering', 'EN'], ['Faculty of Humanities & Sciences', 'HS']];
  const others = [];
  for (let i = 0; i < 44; i++) {
    const [fac, pre] = FAC[i % FAC.length];
    const yr = 21 + (i % 4);
    const u = await S(`${FIRST[i % FIRST.length]} ${LAST[(i * 7) % LAST.length]}`, `${pre}${yr}${String(100000 + i * 3917).slice(0, 6)}`, fac, 4 - (i % 4));
    others.push(u);
    // Spread sign-ups over the last five months for the user statistics report.
    await setCreated(User, u._id, at(T.addDays(today(), -Math.floor(rand() * 150)), '10:00'));
  }
  const inactive = others[0];
  inactive.status = 'deactivated'; inactive.statusReason = 'Graduated';
  await inactive.save();

  // ---------- Appointments ----------
  const used = new Set();
  const A = async (o) => {
    const start = o.start;
    const key = `${o.counsellor._id}:${start.getTime()}`;
    if (used.has(key)) return null;
    used.add(key);
    const len = o.len || 30;
    const conf = o.confirmedAt || plusMin(o.createdAt || start, 60 * 5);
    const history = [{ status: 'pending', label: 'Request sent', by: 'student', at: o.createdAt || plusMin(start, -60 * 24 * 3) }];
    if (['confirmed', 'completed', 'no_show', 'reschedule_requested', 'reschedule_proposed'].includes(o.status)) history.push({ status: 'confirmed', label: 'Confirmed', by: 'counsellor', at: conf });
    if (o.rescheduled) history.push({ status: 'confirmed', label: 'Rescheduled', by: 'student', at: plusMin(conf, 60) });
    if (o.status === 'completed') history.push({ status: 'completed', label: 'Session completed', by: 'counsellor', at: plusMin(start, len) });
    if (o.status === 'cancelled') history.push({ status: 'cancelled', label: 'Cancelled', by: o.cancelBy || 'student', at: plusMin(start, -60 * 30) });
    if (o.status === 'declined') history.push({ status: 'declined', label: 'Declined', by: 'counsellor', at: plusMin(start, -60 * 40) });
    if (o.status === 'no_show') history.push({ status: 'no_show', label: 'Student did not attend', by: 'counsellor', at: plusMin(start, len) });
    const active = ['pending', 'confirmed', 'reschedule_requested', 'reschedule_proposed'].includes(o.status);
    const a = await Appointment.create({
      student: o.student._id, counsellor: o.counsellor._id, start, end: plusMin(start, len), mode: o.mode || 'online',
      location: o.mode === 'in_person' ? (o.counsellor.professional?.room || 'Wellbeing Centre') : 'Online',
      meetingLink: o.mode !== 'in_person' && o.status !== 'pending' ? `https://meet.jit.si/MindBridge-demo-${crypto.randomBytes(4).toString('hex')}` : undefined,
      note: o.note || '', status: o.status, slotLock: active, history,
      duplicateOf: o.duplicateOf || [], flaggedDuplicate: !!o.flagged,
      cancel: o.status === 'cancelled' ? { reason: o.cancelReason || 'Clash with a lab session', by: o.cancelBy || 'student', at: plusMin(start, -60 * 30) } : undefined,
      decline: o.status === 'declined' ? { reason: 'Time is no longer available', message: 'I have openings later in the week.' } : undefined,
      proposal: o.proposal,
      remindersSent: o.remindersSent || { day: false, hour: false },
      session: o.status === 'completed' ? { startedAt: start, endedAt: plusMin(start, len), checklist: [{ label: 'Confidentiality explained', done: true }, { label: 'Consent recorded', done: true }, { label: 'Agree next steps', done: true }] } : undefined,
    });
    await setCreated(Appointment, a._id, o.createdAt || plusMin(start, -60 * 24 * 3));
    return a;
  };

  // Pasindi — one pending request with Dr. Kalupahana (FR4 status), plus history.
  const pasindiReq = await A({ student: pasindi, counsellor: hasini, start: at(workday(3), '10:30'), status: 'pending', mode: 'online', note: 'I’ve been struggling to sleep before exams and it’s affecting my work.', createdAt: new Date(Date.now() - 2 * 3600 * 1000) });
  await A({ student: pasindi, counsellor: nadeesha, start: at(pastWorkday(15), '14:00'), status: 'completed', mode: 'in_person' });
  await A({ student: pasindi, counsellor: kavindu, start: at(pastWorkday(25), '11:00'), status: 'cancelled', mode: 'online' });

  // Today for Dr. Kalupahana
  const next1 = soon(25);
  const dinithiToday = await A({ student: dinithi, counsellor: hasini, start: next1, status: 'confirmed', mode: 'online', remindersSent: { day: true, hour: true }, createdAt: at(pastWorkday(4), '09:00') });
  const d1 = await A({ student: dinithi, counsellor: hasini, start: at(pastWorkday(10), '10:00'), status: 'completed', mode: 'online' });
  const d2 = await A({ student: dinithi, counsellor: hasini, start: at(pastWorkday(5), '10:00'), status: 'completed', mode: 'online' });
  await A({ student: ravindu, counsellor: hasini, start: plusMin(next1, 150), status: 'confirmed', mode: 'online', rescheduled: true, remindersSent: { day: true, hour: false } });
  await A({ student: tharindu, counsellor: hasini, start: at(workday(3), '13:30'), status: 'confirmed', mode: 'in_person' });
  // Pending requests, including Kasun's duplicate (he also holds a confirmed slot with Ms. Fernando).
  const kasunN = await A({ student: kasun, counsellor: nadeesha, start: at(workday(4), '11:00'), status: 'confirmed', mode: 'online', flagged: true });
  const kasunH = await A({ student: kasun, counsellor: hasini, start: at(workday(4), '09:00'), status: 'pending', mode: 'in_person', duplicateOf: [kasunN._id], flagged: true, note: 'Headaches and stress before deadlines.', createdAt: new Date(Date.now() - 5 * 3600 * 1000) });
  await Appointment.updateOne({ _id: kasunN._id }, { $set: { duplicateOf: [kasunH._id] } });
  await A({ student: ishara, counsellor: hasini, start: at(workday(4), '14:30'), status: 'pending', mode: 'online', createdAt: new Date(Date.now() - 26 * 3600 * 1000) });
  await A({ student: amaya, counsellor: shalini, start: at(workday(5), '14:00'), status: 'confirmed', mode: 'in_person' });

  // Session notes for Dinithi (encrypted at rest, author-only).
  await M.SessionNote.create({ appointment: d1._id, counsellor: hasini._id, student: dinithi._id, summary: 'First follow-up. Sleeping 5 hours. Anxious about group presentations.', plan: 'Fixed bedtime. Try box breathing before presentations.', tags: ['Stress', 'Sleep'], goals: [{ text: 'Regular sleep schedule', done: false }, { text: 'Presentation anxiety plan', done: false }] });
  await M.SessionNote.create({ appointment: d2._id, counsellor: hasini._id, student: dinithi._id, summary: 'Sleep improving after keeping a fixed bedtime. Still anxious about group presentations.', plan: 'Rehearse presentation with a friend. Check in about family pressure.', tags: ['Stress', 'Sleep', 'Follow-up needed'], goals: [{ text: 'Regular sleep schedule', done: true }, { text: 'Presentation anxiety plan', done: false }, { text: 'Check in about family pressure', done: false }] });

  // Historical sessions across all counsellors for reports.
  const pool = [...others.slice(1), ...named.slice(1)];
  for (let i = 0; i < 260; i++) {
    const daysAgo = 1 + Math.floor(rand() * 150);
    let d = T.addDays(today(), -daysAgo);
    while (T.weekdayOf(d) > 5) d = T.addDays(d, -1);
    const c = pick(counsellors);
    const time = pick(['09:00', '09:30', '10:00', '10:30', '11:00', '11:30', '13:30', '14:00', '14:30', '15:00']);
    const r = rand();
    const status = r < 0.82 ? 'completed' : r < 0.9 ? 'cancelled' : r < 0.95 ? 'no_show' : 'declined';
    const mode = (c.professional.modes.length === 1 || rand() < 0.6) ? 'online' : 'in_person';
    const start = at(d, time);
    const createdAt = plusMin(start, -60 * 24 * (2 + Math.floor(rand() * 6)));
    await A({ student: pick(pool), counsellor: c, start, status, mode, flagged: rand() < 0.04, rescheduled: rand() < 0.1, createdAt, confirmedAt: plusMin(createdAt, 30 + Math.floor(rand() * 60 * (rand() < 0.9 ? 20 : 40))) });
  }
  // Upcoming bookings made in the last few days by other students (one active booking each).
  for (let i = 1; i <= 26; i++) {
    const d = workday(1 + (i % 9));
    const c = counsellors[i % counsellors.length];
    const av = c.availability;
    const startMin = T.toMinutes(av.startTime) + 30 * ((i * 5) % 8);
    const time = T.fromMinutes(Math.min(startMin, T.toMinutes(av.endTime) - 30));
    if (!av.workingDays.includes(T.weekdayOf(d)) || av.blocks.some((b) => b.date === d) || (av.lunchBreak.enabled && time >= av.lunchBreak.start && time < av.lunchBreak.end)) continue;
    const createdAt = new Date(Date.now() - (1 + Math.floor(rand() * 40)) * 3600 * 1000);
    await A({ student: others[i + 1], counsellor: c, start: at(d, time), status: rand() < 0.75 ? 'confirmed' : 'pending', mode: c.professional.modes.length === 1 || rand() < 0.6 ? 'online' : 'in_person', createdAt, confirmedAt: plusMin(createdAt, 60 + Math.floor(rand() * 400)) });
  }

  // ---------- Referrals & consultations ----------
  const refPasindi = await M.Referral.create({ counsellor: hasini._id, doctor: ruwan._id, student: pasindi._id, appointment: pasindiReq._id, urgency: 'priority', reason: 'Persistent insomnia for 6 weeks affecting daily function. Please assess.', summary: 'Two sessions. Sleep 4–5 h a night. No medication.', contact: pasindi.phone, share: { summary: true, contact: true, fullNotes: false }, consent: true, status: 'new' });
  await setCreated(M.Referral, refPasindi._id, new Date(Date.now() - 3 * 3600 * 1000));
  const refKasun = await M.Referral.create({ counsellor: nadeesha._id, doctor: ruwan._id, student: kasun._id, appointment: kasunN._id, urgency: 'routine', reason: 'Frequent tension headaches during deadline weeks. Please rule out physical causes.', summary: 'Headaches 3–4 times a week, worse in the evening.', contact: kasun.phone, share: { summary: true, contact: true, fullNotes: false }, consent: true, status: 'new' });
  await setCreated(M.Referral, refKasun._id, new Date(Date.now() - 26 * 3600 * 1000));
  const refDinithi = await M.Referral.create({ counsellor: hasini._id, doctor: ruwan._id, student: dinithi._id, appointment: d2._id, urgency: 'routine', reason: 'Ongoing sleep difficulty; would benefit from a medical review.', summary: 'Sleep improving with routine, still 5–6 h.', contact: dinithi.phone, share: { summary: true, contact: true, fullNotes: false }, consent: true, status: 'accepted' });
  const refTharindu = await M.Referral.create({ counsellor: hasini._id, doctor: ruwan._id, student: tharindu._id, urgency: 'routine', reason: 'Low appetite and fatigue for several weeks.', summary: 'Mood mostly okay, energy low.', contact: tharindu.phone, share: { summary: true, contact: true, fullNotes: false }, consent: true, status: 'accepted' });
  const refAmaya = await M.Referral.create({ counsellor: shalini._id, doctor: ruwan._id, student: amaya._id, urgency: 'routine', reason: 'Recurring stomach pain before exams.', summary: '', contact: amaya.phone, share: { summary: false, contact: true, fullNotes: false }, consent: true, status: 'accepted' });

  const ruwanRoom = ruwan.professional.room;
  const c1 = await M.Consultation.create({ doctor: ruwan._id, student: dinithi._id, referral: refDinithi._id, start: soon(60), end: plusMin(soon(60), 30), mode: 'online', room: 'Online' });
  const c2 = await M.Consultation.create({ doctor: ruwan._id, student: amaya._id, referral: refAmaya._id, start: soon(240), end: plusMin(soon(240), 30), mode: 'in_person', room: ruwanRoom });
  const tPrev = await M.Consultation.create({ doctor: ruwan._id, student: tharindu._id, referral: refTharindu._id, start: at(pastWorkday(8), '09:30'), end: at(pastWorkday(8), '10:00'), mode: 'in_person', room: ruwanRoom, status: 'completed', startedAt: at(pastWorkday(8), '09:31'), endedAt: at(pastWorkday(8), '09:55'), vitals: { bloodPressure: '120/78', avgSleep: '6 h' }, assessment: 'Fatigue likely lifestyle-related. Bloods ordered.', tags: ['Lifestyle advice', 'Follow-up'], clinicalNotes: 'No red flags. Discussed diet and sleep.', plan: 'Blood test results review in 2 weeks.', shareSummary: true });
  await M.Consultation.create({ doctor: ruwan._id, student: tharindu._id, referral: refTharindu._id, followUpOf: tPrev._id, start: at(workday(2), '09:30'), end: at(workday(2), '10:00'), mode: 'in_person', room: ruwanRoom });
  refDinithi.consultation = c1._id; await refDinithi.save();
  refAmaya.consultation = c2._id; await refAmaya.save();
  refTharindu.consultation = tPrev._id; await refTharindu.save();

  // ---------- Articles ----------
  const authors = { hasini, nadeesha, kavindu, shalini };
  const arts = {};
  for (const [i, a] of ARTICLES.entries()) {
    const when = at(T.addDays(today(), -(i + 2)), '10:00');
    const doc = await M.Article.create({ ...a, author: authors[a.author]._id, publishedAt: a.status === 'published' ? when : undefined, submittedAt: a.status !== 'draft' ? when : undefined });
    await setCreated(M.Article, doc._id, when);
    arts[a.title] = doc;
  }
  pasindi.savedArticles = [arts['Sleeping well during exam weeks']._id, arts['Five-minute mindfulness between lectures']._id, arts['When everything feels urgent']._id];
  await pasindi.save();

  // ---------- Relaxing music (no audio yet: these play as timed demos until an admin uploads MP3s) ----------
  await M.Track.insertMany([
    ['Rain on the Library Roof', 'Calm Sounds', 'Rain', 252, 'graphic_eq', 'green'],
    ['Slow Morning', 'Piano', 'Focus', 220, 'music_note', 'lilac'],
    ['Kandy Forest Walk', 'Nature', 'Nature', 365, 'forest', 'green'],
    ['Study Drift', 'Lo-fi', 'Lo-fi', 318, 'music_note', 'blue'],
    ['Night Waves', 'Calm Sounds', 'Sleep', 410, 'bedtime', 'lilac'],
    ['Monsoon Window', 'Calm Sounds', 'Rain', 290, 'water_drop', 'blue'],
    ['Deep Focus Hum', 'Ambient', 'Focus', 600, 'graphic_eq', 'amber'],
    ['Sinharaja Morning', 'Nature', 'Nature', 330, 'forest', 'green'],
  ].reverse().map(([title, artist, category, seconds, icon, tone]) => ({ title, artist, category, seconds, icon, tone }))); // newest first in the app

  // ---------- Mood, journal and chat (Pasindi) ----------
  const FACTORS = ['Exams', 'Assignments', 'Sleep', 'Friends', 'Family', 'Money', 'Health'];
  for (let i = 45; i >= 1; i--) {
    if (i > 4 && rand() < 0.3) continue; // streak: last 4 days are all checked in
    const d = T.addDays(today(), -i);
    const examWeek = i >= 18 && i <= 24;
    const mood = Math.max(0, Math.min(4, Math.round((examWeek ? 1.6 : 2.9) + (rand() - 0.5) * 2)));
    const fs2 = examWeek ? ['Exams', pick(['Sleep', 'Assignments'])] : (rand() < 0.4 ? [pick(FACTORS)] : []);
    await M.MoodEntry.create({ student: pasindi._id, mood, factors: [...new Set(fs2)], date: d, note: mood <= 1 ? 'Three deadlines this week.' : '' });
  }
  // Anonymous check-ins from other students (reports).
  for (let i = 0; i < 420; i++) {
    const d = T.addDays(today(), -Math.floor(rand() * 120));
    await M.MoodEntry.create({ student: pick(others)._id, mood: Math.floor(rand() * 5), factors: rand() < 0.5 ? [pick(FACTORS)] : [], date: d });
  }

  const J = [
    ['Calming the presentation nerves', 'I was dreading the group presentation all week. Practising twice with friends helped more than I expected. My hands still shook at the start, but after the first slide it felt manageable.\n\nNext time I want to try the box breathing exercise before I go in.', 2, ['Academic'], 0],
    ['Reflections on midterm week', 'I studied late every night and by Thursday I couldn’t focus at all. Next exam period I want to keep a proper bedtime, even if it feels like I’m losing study time.', 1, ['Academic', 'Health'], 4],
    ['Small wins', 'Finished the DB assignment early. Went for a walk with Sachini after and actually enjoyed the evening.', 3, ['Gratitude'], 7],
  ];
  for (const [title, body, mood, tags, ago] of J) {
    const j = await M.JournalEntry.create({ student: pasindi._id, title, body, mood, tags });
    await setCreated(M.JournalEntry, j._id, at(T.addDays(today(), -ago), '20:12'));
  }

  const chat = [['ai', 'Hi Pasindi. How are you feeling today?'], ['me', 'Honestly a bit overwhelmed. I have three deadlines this week.'], ['ai', 'That’s a lot at once. Would it help to break them down together, or try a short breathing exercise first?']];
  for (const [i, [from, text]] of chat.entries()) {
    const m = await M.ChatMessage.create({ student: pasindi._id, from, text });
    await setCreated(M.ChatMessage, m._id, new Date(Date.now() - (3 - i) * 60000 - 86400000));
  }

  // ---------- Wellness events ----------
  const KINDS = [['article_read', 30], ['bridge_chat', 22], ['breathing', 18], ['game', 14], ['music', 12], ['helpline_tap', 2], ['bridge_escalation', 1]];
  const total = KINDS.reduce((t, [, w]) => t + w, 0);
  for (let i = 0; i < 900; i++) {
    let r = rand() * total; let kind = 'article_read';
    for (const [k, w] of KINDS) { if (r < w) { kind = k; break; } r -= w; }
    const e = await M.WellnessEvent.create({ user: pick(others)._id, kind, durationSec: kind === 'breathing' ? 120 : kind === 'music' ? 600 : undefined });
    await setCreated(M.WellnessEvent, e._id, new Date(Date.now() - Math.floor(rand() * 60) * 86400000));
  }
  for (let i = 0; i < 6; i++) {
    const e = await M.WellnessEvent.create({ user: pasindi._id, kind: 'breathing', durationSec: 120 + (i % 3) * 30 });
    await setCreated(M.WellnessEvent, e._id, at(T.addDays(T.weekStart(today()), Math.min(i, 6)), '19:00'));
  }

  // ---------- Notifications ----------
  const N = (u, o, minsAgo, read = false) => M.Notification.create({ user: u._id, read, ...o }).then((n) => setCreated(M.Notification, n._id, new Date(Date.now() - minsAgo * 60000)));
  await N(pasindi, { type: 'reminder', title: 'Reminder: request pending', body: `Dr. Kalupahana usually replies within 24 hours.`, icon: 'hourglass_top', tone: 'amber', link: { screen: 'appointment', id: pasindiReq.id } }, 40);
  await N(pasindi, { type: 'article', title: 'New article: Sleeping well in exam weeks', body: 'By Ms. Nadeesha Fernando', icon: 'article', tone: 'amber', link: { screen: 'article', id: arts['Sleeping well during exam weeks'].id } }, 60 * 30, true);
  await N(pasindi, { type: 'checkin', title: 'Daily check-in', body: 'Take 30 seconds to note how you’re feeling.', icon: 'self_improvement', tone: 'lilac', link: { screen: 'checkin' } }, 60 * 26, true);
  await N(hasini, { type: 'booking_request', title: 'New booking request', body: `Pasindi Perera · ${T.fmtDateTime(pasindiReq.start)}`, icon: 'inbox', tone: 'amber', link: { screen: 'request', id: pasindiReq.id } }, 120);
  await N(hasini, { type: 'duplicate', title: 'Possible duplicate booking', body: 'Kasun Wijeratne has 2 active requests', icon: 'content_copy', tone: 'red', link: { screen: 'request', id: kasunH.id } }, 300);
  await N(hasini, { type: 'referral', title: 'Referral accepted', body: 'Dr. Dissanayake accepted Dinithi’s referral', icon: 'local_hospital', tone: 'green', link: { screen: 'referral', id: refDinithi.id } }, 60 * 30, true);
  await N(ruwan, { type: 'referral', title: 'Priority referral', body: 'Pasindi Perera · from Dr. Hasini Kalupahana', icon: 'priority_high', tone: 'red', link: { screen: 'referral', id: refPasindi.id } }, 180);
  await N(ruwan, { type: 'referral', title: 'Routine referral', body: 'Kasun Wijeratne · from Ms. Nadeesha Fernando', icon: 'assignment_ind', tone: 'amber', link: { screen: 'referral', id: refKasun.id } }, 60 * 26, true);
  await N(admin, { type: 'verification', title: 'New counsellor application', body: 'Tharushi Wijesekara', icon: 'person_add', tone: 'blue', link: { screen: 'verification' } }, 60 * 2);
  await N(admin, { type: 'article', title: 'Article submitted for review', body: 'Homesick in first year', icon: 'article', tone: 'amber', link: { screen: 'article_review', id: arts['Homesick in first year'].id } }, 60 * 26);

  // ---------- Activity log ----------
  const L = async (cat, action, target, minsAgo) => {
    const l = await M.AuditLog.create({ actor: admin._id, actorName: admin.name, category: cat, action, target });
    await setCreated(M.AuditLog, l._id, new Date(Date.now() - minsAgo * 60000));
  };
  await L('verification', 'Counsellor approved', 'Mr. Kavindu Jayasinghe', 60 * 24 * 20);
  await L('articles', 'Article approved', 'Sleeping well during exam weeks', 60 * 24 * 2);
  await L('settings', 'Setting changed', 'appointments: bookingWindowDays → 21', 60 * 24 * 3);
  await L('users', 'Account deactivated', `${inactive.name} — Graduated`, 60 * 24);

  log('[seed] done.');
  log(`[seed] demo password for every account: ${PASSWORD}`);
  log('[seed] student: it23714052@my.sliit.lk · counsellor: hasini.k@sliit.lk · doctor: ruwan.d@sliit.lk · admin: malsha.g@sliit.lk');
}

module.exports = { seed };

if (require.main === module) {
  const { connectDb, disconnectDb } = require('../config/db');
  connectDb()
    .then(() => seed())
    .then(() => disconnectDb())
    .catch((e) => { console.error(e); process.exit(1); });
}
