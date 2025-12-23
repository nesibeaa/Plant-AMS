import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_container.dart';
import '../../state/auth_state.dart';
import '../../services/auth_service.dart';

class RegisterPage extends StatefulWidget {
  final VoidCallback onNavigateToLogin;

  const RegisterPage({
    super.key,
    required this.onNavigateToLogin,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final authService = AuthService();
    final result = await authService.register(
      email: _emailController.text.trim(),
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      fullName: _fullNameController.text.trim().isEmpty
          ? null
          : _fullNameController.text.trim(),
    );

    setState(() {
      _isLoading = false;
    });

    if (result['success'] == true) {
      // AuthState'i güncelle
      final authState = context.read<AuthState>();
      await authState.refresh();
    } else {
      setState(() {
        _errorMessage = result['error'] ?? 'Kayıt başarısız. Email veya kullanıcı adı zaten kullanılıyor olabilir.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),
                  // Back button
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: widget.onNavigateToLogin,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // Logo/Icon
                  Container(
                    height: 80,
                    width: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: LinearGradient(
                        colors: [
                          AppColors.cyan,
                          AppColors.cyan.withOpacity(0.7),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Icon(
                      Icons.local_florist,
                      size: 40,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Hesap Oluştur',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yeni bir hesap oluşturun ve başlayın',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.white70,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  GlassContainer(
                    borderRadius: 20,
                    padding: const EdgeInsets.all(24),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_errorMessage != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppColors.danger.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: AppColors.danger.withOpacity(0.5),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.error_outline,
                                    color: AppColors.danger,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: theme.textTheme.bodySmall?.copyWith(
                                        color: AppColors.danger,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                          ],
                          TextFormField(
                            controller: _fullNameController,
                            decoration: const InputDecoration(
                              labelText: 'Ad Soyad (Opsiyonel)',
                              prefixIcon: Icon(Icons.person),
                            ),
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.name,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _emailController,
                            decoration: const InputDecoration(
                              labelText: 'E-posta',
                              prefixIcon: Icon(Icons.email_outlined),
                            ),
                            textInputAction: TextInputAction.next,
                            keyboardType: TextInputType.emailAddress,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen e-posta adresinizi girin';
                              }
                              if (!value.contains('@')) {
                                return 'Geçerli bir e-posta adresi girin';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _usernameController,
                            decoration: const InputDecoration(
                              labelText: 'Kullanıcı Adı',
                              prefixIcon: Icon(Icons.alternate_email),
                            ),
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen kullanıcı adı girin';
                              }
                              if (value.length < 3) {
                                return 'Kullanıcı adı en az 3 karakter olmalıdır';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscurePassword,
                            textInputAction: TextInputAction.next,
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen şifrenizi girin';
                              }
                              if (value.length < 6) {
                                return 'Şifre en az 6 karakter olmalıdır';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _confirmPasswordController,
                            decoration: InputDecoration(
                              labelText: 'Şifre Tekrar',
                              prefixIcon: const Icon(Icons.lock_outline),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscureConfirmPassword
                                      ? Icons.visibility_outlined
                                      : Icons.visibility_off_outlined,
                                ),
                                onPressed: () {
                                  setState(() {
                                    _obscureConfirmPassword = !_obscureConfirmPassword;
                                  });
                                },
                              ),
                            ),
                            obscureText: _obscureConfirmPassword,
                            textInputAction: TextInputAction.done,
                            onFieldSubmitted: (_) => _handleRegister(),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Lütfen şifrenizi tekrar girin';
                              }
                              if (value != _passwordController.text) {
                                return 'Şifreler eşleşmiyor';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _handleRegister,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.cyan,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: _isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
                                        Colors.black,
                                      ),
                                    ),
                                  )
                                : Text(
                                    'Kayıt Ol',
                                    style: theme.textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: Colors.black,
                                    ),
                                  ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Zaten hesabınız var mı? ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      TextButton(
                        onPressed: widget.onNavigateToLogin,
                        child: Text(
                          'Giriş Yap',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: AppColors.cyan,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

