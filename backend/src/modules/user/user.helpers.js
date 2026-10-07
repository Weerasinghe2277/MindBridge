// Helpers shared by the user and counsellor-approval modules (and the admin dashboard).
const User = require('../../models/User');
const { isValidId } = require('../../middleware/validate');
const { notFound } = require('../../utils/errors');

const ROLE_LABEL = { student: 'Student', counsellor: 'Counsellor', doctor: 'Doctor', admin: 'Admin' };

function userRow(u) {
  const v = u.verification?.status;
  let badge = u.status === 'active' ? ['Active', 'green'] : ['Inactive', 'grey'];
  if (u.isStaff && v !== 'approved') badge = v === 'rejected' ? ['Rejected', 'red'] : v === 'changes_requested' ? ['Changes asked', 'blue'] : ['Pending', 'amber'];
  return {
    id: u.id, name: u.name, initials: u.initials, email: u.email, role: u.role, roleLabel: ROLE_LABEL[u.role],
    studentId: u.studentId, status: u.status, verification: v, badge: badge[0], badgeTone: badge[1], createdAt: u.createdAt,
  };
}

async function loadUser(id) {
  if (!isValidId(id)) throw notFound('User not found.');
  const u = await User.findById(id);
  if (!u) throw notFound('User not found.');
  return u;
}

module.exports = { ROLE_LABEL, userRow, loadUser };
