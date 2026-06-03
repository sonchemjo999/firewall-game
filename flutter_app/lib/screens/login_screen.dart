import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../widgets/shield_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _keyCtrl = TextEditingController();
  bool _isRegister = false;
  bool _loading = false;
  bool _obscure = true;
  String? _error;
  late AnimationController _animCtrl;
  late AnimationController _pulseCtrl;
  late Animation<double> _fadeAnim;
  late Animation<double> _slideAnim;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
    _fadeAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _slideAnim = Tween<double>(begin: 30, end: 0).animate(
        CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic));
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _animCtrl.forward();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _pulseCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _keyCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_usernameCtrl.text.isEmpty || _passwordCtrl.text.isEmpty) {
      setState(() => _error = 'Vui long nhap day du thong tin');
      return;
    }
    setState(() { _loading = true; _error = null; });
    final api = context.read<ApiService>();
    final auth = context.read<AuthService>();
    try {
      Map<String, dynamic> res;
      if (_isRegister) {
        if (_keyCtrl.text.isEmpty) {
          setState(() { _error = 'Vui long nhap License Key'; _loading = false; });
          return;
        }
        res = await api.register(_usernameCtrl.text, _passwordCtrl.text, _keyCtrl.text);
      } else {
        res = await api.login(_usernameCtrl.text, _passwordCtrl.text);
      }
      final user = res['user'] as Map<String, dynamic>;
      await auth.login(
        res['token'], user['username'], user['role'],
        planSlug: user['plan_slug']?.toString(),
        planName: user['plan_name']?.toString(),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceAll('Exception: ', ''));
    }
    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.of(context).size.height;
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF080C14), Color(0xFF0D1220), Color(0xFF0A0F1A)],
          ),
        ),
        child: Stack(
          children: [
            // Grid pattern background
            Positioned.fill(
              child: CustomPaint(painter: _GridPainter()),
            ),
            // Content
            Center(
              child: FadeTransition(
                opacity: _fadeAnim,
                child: AnimatedBuilder(
                  animation: _slideAnim,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, _slideAnim.value),
                    child: child,
                  ),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        AnimatedBuilder(
                          animation: _pulseCtrl,
                          builder: (context, child) => Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF6C63FF).withOpacity(0.15 + 0.1 * _pulseCtrl.value),
                                  blurRadius: 25 + 10 * _pulseCtrl.value,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: const ShieldLogo(size: 90),
                          ),
                        ),
                        const SizedBox(height: 20),
                        ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            colors: [Color(0xFF6C63FF), Color(0xFF00D9FF)],
                          ).createShader(bounds),
                          child: const Text('NRO Shield',
                            style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: -0.5)),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [const Color(0xFF6C63FF).withOpacity(0.2), const Color(0xFF00D9FF).withOpacity(0.2)],
                            ),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF6C63FF).withOpacity(0.3)),
                          ),
                          child: const Text('Advanced DDoS Protection v2.0',
                              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12, letterSpacing: 0.5)),
                        ),
                        const SizedBox(height: 40),
                        // Login Card
                        Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F1520),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFF1A2332)),
                            boxShadow: [
                              BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 30, offset: const Offset(0, 10)),
                            ],
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(28),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF6C63FF).withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Icon(_isRegister ? Icons.person_add : Icons.login,
                                          color: const Color(0xFF6C63FF), size: 20),
                                    ),
                                    const SizedBox(width: 12),
                                    Text(_isRegister ? 'Tao tai khoan' : 'Dang nhap',
                                        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                                  ],
                                ),
                                const SizedBox(height: 24),
                                _buildField(_usernameCtrl, 'Ten dang nhap', Icons.person_outline, false),
                                const SizedBox(height: 16),
                                _buildField(_passwordCtrl, 'Mat khau', Icons.lock_outline, true),
                                if (_isRegister) ...[
                                  const SizedBox(height: 16),
                                  _buildField(_keyCtrl, 'License Key', Icons.vpn_key_outlined, false, hint: 'NRO-XXXX-XXXX-XXXX'),
                                ],
                                if (_error != null) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF4757).withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFFFF4757).withOpacity(0.2)),
                                    ),
                                    child: Row(children: [
                                      const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF4757), size: 18),
                                      const SizedBox(width: 8),
                                      Expanded(child: Text(_error!, style: const TextStyle(color: Color(0xFFFF4757), fontSize: 13))),
                                    ]),
                                  ),
                                ],
                                const SizedBox(height: 24),
                                SizedBox(
                                  height: 52,
                                  child: ElevatedButton(
                                    onPressed: _loading ? null : _submit,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C63FF),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                      elevation: 0,
                                    ),
                                    child: _loading
                                        ? const SizedBox(width: 22, height: 22,
                                            child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                            Text(_isRegister ? 'Dang ky' : 'Dang nhap',
                                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                            const SizedBox(width: 8),
                                            const Icon(Icons.arrow_forward, size: 18),
                                          ]),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Center(
                                  child: TextButton(
                                    onPressed: () => setState(() { _isRegister = !_isRegister; _error = null; }),
                                    child: Text.rich(TextSpan(
                                      children: [
                                        TextSpan(text: _isRegister ? 'Da co tai khoan? ' : 'Chua co tai khoan? ',
                                            style: TextStyle(color: Colors.grey[500])),
                                        TextSpan(text: _isRegister ? 'Dang nhap' : 'Dang ky',
                                            style: const TextStyle(color: Color(0xFF6C63FF), fontWeight: FontWeight.w600)),
                                      ],
                                    )),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 30),
                        // Features row
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _featureChip(Icons.shield, '9 Games'),
                            const SizedBox(width: 12),
                            _featureChip(Icons.speed, 'Real-time'),
                            const SizedBox(width: 12),
                            _featureChip(Icons.smart_toy, 'AI Engine'),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(TextEditingController ctrl, String label, IconData icon, bool isPassword, {String? hint}) {
    return TextField(
      controller: ctrl,
      obscureText: isPassword ? _obscure : false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        suffixIcon: isPassword
            ? IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
                onPressed: () => setState(() => _obscure = !_obscure),
              )
            : null,
      ),
      textInputAction: TextInputAction.next,
      onSubmitted: !_isRegister && !isPassword ? null : (_) => _submit(),
    );
  }

  Widget _featureChip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF141C2B),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF1E293B)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: const Color(0xFF00D9FF)),
        const SizedBox(width: 6),
        Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
      ]),
    );
  }
}

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A2332).withOpacity(0.3)
      ..strokeWidth = 0.5;
    const spacing = 40.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
