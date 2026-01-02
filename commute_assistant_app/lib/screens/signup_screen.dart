import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../widgets/address_autocomplete_field.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _nameController = TextEditingController();
  final _homeAddressController = TextEditingController();
  final _homeDetailAddressController = TextEditingController();
  final _workAddressController = TextEditingController();
  final _workDetailAddressController = TextEditingController();
  
  String _selectedGender = 'male';
  bool _obscurePassword = true;
  bool _obscurePasswordConfirm = true;
  String? _homeAddress;
  String? _workAddress;
  TimeOfDay _workStartTime = const TimeOfDay(hour: 9, minute: 0);

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _nameController.dispose();
    _homeAddressController.dispose();
    _homeDetailAddressController.dispose();
    _workAddressController.dispose();
    _workDetailAddressController.dispose();
    super.dispose();
  }

  Future<void> _handleSignup() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_homeAddress == null || _workAddress == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('집 주소와 회사 주소를 모두 선택해주세요'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 주소와 상세주소 합치기
    String finalHomeAddress = _homeAddress!;
    if (_homeDetailAddressController.text.trim().isNotEmpty) {
      finalHomeAddress = '$_homeAddress ${_homeDetailAddressController.text.trim()}';
    }
    
    String finalWorkAddress = _workAddress!;
    if (_workDetailAddressController.text.trim().isNotEmpty) {
      finalWorkAddress = '$_workAddress ${_workDetailAddressController.text.trim()}';
    }
    
    // 시간을 HH:MM 형식으로 변환
    final workStartTimeStr = '${_workStartTime.hour.toString().padLeft(2, '0')}:${_workStartTime.minute.toString().padLeft(2, '0')}';
    
    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.signup(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
      name: _nameController.text.trim(),
      gender: _selectedGender,
      homeAddress: finalHomeAddress,
      workAddress: finalWorkAddress,
      workStartTime: workStartTimeStr,
    );

    if (mounted) {
      if (success) {
        Navigator.of(context).pop(); // 회원가입 화면 닫기
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('회원가입이 완료되었습니다. 로그인해주세요.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(authProvider.error ?? '회원가입에 실패했습니다'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('회원가입'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 아이디
                TextFormField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: '아이디',
                    hintText: '4자 이상 입력하세요',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '아이디를 입력해주세요';
                    }
                    if (value.length < 4) {
                      return '아이디는 4자 이상이어야 합니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 비밀번호
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: '비밀번호',
                    hintText: '6자 이상 입력하세요',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePassword = !_obscurePassword;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '비밀번호를 입력해주세요';
                    }
                    if (value.length < 6) {
                      return '비밀번호는 6자 이상이어야 합니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 비밀번호 확인
                TextFormField(
                  controller: _passwordConfirmController,
                  obscureText: _obscurePasswordConfirm,
                  decoration: InputDecoration(
                    labelText: '비밀번호 확인',
                    hintText: '비밀번호를 다시 입력하세요',
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePasswordConfirm ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() {
                          _obscurePasswordConfirm = !_obscurePasswordConfirm;
                        });
                      },
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return '비밀번호 확인을 입력해주세요';
                    }
                    if (value != _passwordController.text) {
                      return '비밀번호가 일치하지 않습니다';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 이름
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: '이름',
                    hintText: '이름을 입력하세요',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '이름을 입력해주세요';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // 성별
                DropdownButtonFormField<String>(
                  initialValue: _selectedGender,
                  decoration: InputDecoration(
                    labelText: '성별',
                    prefixIcon: const Icon(Icons.person_outline),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'male', child: Text('남성')),
                    DropdownMenuItem(value: 'female', child: Text('여성')),
                    DropdownMenuItem(value: 'other', child: Text('기타')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedGender = value;
                      });
                    }
                  },
                ),
                const SizedBox(height: 16),
                // 집 주소
                AddressAutocompleteField(
                  controller: _homeAddressController,
                  hintText: '집 주소',
                  dotColor: Colors.blue.shade700,
                  onAddressSelected: (address, lat, lng) {
                    setState(() {
                      _homeAddress = address;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // 집 상세주소
                TextFormField(
                  controller: _homeDetailAddressController,
                  decoration: InputDecoration(
                    labelText: '집 상세주소',
                    hintText: '동/호수 등을 입력하세요',
                    prefixIcon: const Icon(Icons.home_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 회사 주소
                AddressAutocompleteField(
                  controller: _workAddressController,
                  hintText: '회사 주소',
                  dotColor: Colors.orange.shade700,
                  onAddressSelected: (address, lat, lng) {
                    setState(() {
                      _workAddress = address;
                    });
                  },
                ),
                const SizedBox(height: 12),
                // 회사 상세주소
                TextFormField(
                  controller: _workDetailAddressController,
                  decoration: InputDecoration(
                    labelText: '회사 상세주소',
                    hintText: '층/호수 등을 입력하세요',
                    prefixIcon: const Icon(Icons.business_outlined),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // 출근 시간
                InkWell(
                  onTap: () async {
                    final TimeOfDay? picked = await showTimePicker(
                      context: context,
                      initialTime: _workStartTime,
                      builder: (context, child) {
                        return MediaQuery(
                          data: MediaQuery.of(context).copyWith(
                            alwaysUse24HourFormat: true,
                          ),
                          child: child!,
                        );
                      },
                    );
                    if (picked != null && picked != _workStartTime) {
                      setState(() {
                        _workStartTime = picked;
                      });
                    }
                  },
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: '출근 시간',
                      prefixIcon: const Icon(Icons.access_time),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: const Icon(Icons.arrow_drop_down),
                    ),
                    child: Text(
                      '${_workStartTime.hour.toString().padLeft(2, '0')}:${_workStartTime.minute.toString().padLeft(2, '0')}',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                // 회원가입 버튼
                ElevatedButton(
                  onPressed: _handleSignup,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '회원가입',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

