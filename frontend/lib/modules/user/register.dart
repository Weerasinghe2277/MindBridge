// MEMBER 2 — User Management: sign up.
import 'package:flutter/material.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../../features/auth/code_verify.dart';
import '../../features/auth/forgot_password.dart';
import '../../widgets/page.dart';
import '../../widgets/ui.dart';

const faculties = ['Faculty of Computing', 'Faculty of Business', 'Faculty of Engineering', 'Faculty of Humanities & Sciences', 'School of Architecture'];

/// M1-02 — registration for students, counsellors and doctors (FR1, FR11).
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key, this.initialRole = 0});
  final int initialRole;

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  late int _role = widget.initialRole; // 0 student, 1 counsellor, 2 doctor
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _studentId = TextEditingController();
  final _password = TextEditingController();
  final _title = TextEditingController();
  final _qual = TextEditingController();
  final _reg = TextEditingController();
  final _exp = TextEditingController();
  String? _faculty;
  int? _year;
  bool _agree = false;
  bool _busy = false;
  final Map<String, String> _errors = {};

  @override
  void dispose() {
    for (final c in [_name, _email, _studentId, _password, _title, _qual, _reg, _exp]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _student => _role == 0;

  bool _validate() {
    _errors.clear();
    if (_name.text.trim().length < 2) _errors['name'] = 'Enter your full name';
    final email = _email.text.trim().toLowerCase();
    if (!email.contains('@')) {
      _errors['email'] = 'Enter a valid email address';
    } else if (_student && !email.endsWith('@my.sliit.lk')) {
      _errors['email'] = 'Use your @my.sliit.lk address';
    } else if (!_student && !email.endsWith('@sliit.lk')) {
      _errors['email'] = 'Use your @sliit.lk staff address';
    }
    if (_student) {
      if (!RegExp(r'^[A-Za-z]{2}\d{8}$').hasMatch(_studentId.text.trim())) _errors['studentId'] = 'Enter a valid student ID, e.g. IT23714052';
      if (_faculty == null) _errors['faculty'] = 'Choose your faculty';
    } else {
      if (_title.text.trim().isEmpty) _errors['title'] = 'Add your professional title';
      if (_reg.text.trim().isEmpty) _errors['registrationNo'] = 'Add your registration number';
    }
    if (!PasswordRules.valid(_password.text)) _errors['password'] = 'Use 8+ characters with a number';
    if (!_agree) _errors['agreePrivacy'] = 'Please agree to the privacy policy';
    setState(() {});
    return _errors.isEmpty;
  }

  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _busy = true);
    try {
      final body = <String, dynamic>{
        'role': ['student', 'counsellor', 'doctor'][_role],
        'name': _name.text.trim(),
        'email': _email.text.trim().toLowerCase(),
        'password': _password.text,
        'agreePrivacy': true,
        if (_student) ...{'studentId': _studentId.text.trim().toUpperCase(), 'faculty': _faculty, if (_year != null) 'year': _year},
        if (!_student)
          'professional': {
            'title': _title.text.trim(),
            'qualifications': _qual.text.trim(),
            'registrationNo': _reg.text.trim(),
            if (int.tryParse(_exp.text.trim()) != null) 'experienceYears': int.parse(_exp.text.trim()),
          },
      };
      final r = await api.post('/auth/register', body);
      if (!mounted) return;
      replace(context, CodeVerifyScreen(purpose: CodePurpose.verifyEmail, email: r['email'] as String, devOtp: r['devOtp'] as String?), root: true);
    } on ApiException catch (e) {
      final f = e.field;
      setState(() {
        if (f != null && f != 'professional') {
          _errors[f] = e.message;
        } else {
          _errors['form'] = e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MbPage(
      title: 'Create account',
      bg: PageBg.white,
      children: [
        Segmented(items: const ['Student', 'Counsellor', 'Doctor'], index: _role, onChanged: (i) => setState(() {
              _role = i;
              _errors.clear();
            })),
        MbField(label: 'Full name', controller: _name, error: _errors['name'], capitalization: TextCapitalization.words, autofill: const [AutofillHints.name]),
        MbField(label: _student ? 'University email' : 'Staff email', controller: _email, type: FieldType.email, error: _errors['email'], helper: _student ? 'Use your @my.sliit.lk address' : 'Use your @sliit.lk staff address', autofill: const [AutofillHints.email]),
        if (_student) ...[
          MbField(label: 'Student ID', controller: _studentId, hint: 'IT23714052', error: _errors['studentId'], capitalization: TextCapitalization.characters),
          MbField(label: 'Faculty', type: FieldType.select, value: _faculty, hint: 'Choose your faculty', error: _errors['faculty'], onTap: () async {
            final v = await pickOption(context, title: 'Faculty', options: faculties, current: _faculty);
            if (v != null) setState(() => _faculty = v);
          }),
          MbField(label: 'Year of study (optional)', type: FieldType.select, value: _year == null ? null : 'Year $_year', hint: 'Choose', onTap: () async {
            final v = await pickOption(context, title: 'Year of study', options: const ['Year 1', 'Year 2', 'Year 3', 'Year 4'], current: _year == null ? null : 'Year $_year');
            if (v != null) setState(() => _year = int.parse(v.split(' ').last));
          }),
        ] else ...[
          MbField(label: 'Professional title', controller: _title, hint: _role == 1 ? 'e.g. Counsellor, Clinical Psychologist' : 'e.g. Medical Officer', error: _errors['title']),
          MbField(label: 'Qualifications', controller: _qual, type: FieldType.area, rows: 2, hint: 'e.g. MSc Counselling Psychology'),
          MbField(label: _role == 1 ? 'Professional registration (SLPA / SLNCC)' : 'SLMC registration', controller: _reg, error: _errors['registrationNo'], hint: _role == 1 ? 'e.g. SLNCC 2219' : 'e.g. SLMC 31207'),
          MbField(label: 'Years of experience (optional)', controller: _exp, type: FieldType.number),
        ],
        MbField(label: 'Password', controller: _password, type: FieldType.password, hint: 'At least 8 characters', error: _errors['password'], helper: 'Use 8+ characters with a number', autofill: const [AutofillHints.newPassword]),
        ToggleTile(title: 'I agree to the privacy policy', sub: 'We never share your data with lecturers or parents.', value: _agree, onChanged: (v) => setState(() => _agree = v)),
        if (_errors['agreePrivacy'] != null) Text(_errors['agreePrivacy']!, style: Ty.nunito(size: 12.5, weight: FontWeight.w600, color: C.dangerText)),
        if (!_student) const BannerCard(tone: Tone.blue, icon: 'upload_file', text: 'After verifying your email you’ll upload your degree, registration certificate and ID for Student Affairs to review.'),
        if (_errors['form'] != null) BannerCard(tone: Tone.red, icon: 'error', text: _errors['form']),
      ],
      foot: [MbButton(_student ? 'Create account' : 'Apply for verification', loading: _busy, onPressed: _submit)],
      footNote: 'Counsellor and doctor accounts are verified by Student Affairs',
    );
  }
}
