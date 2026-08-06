import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/activity_tracker.dart';
import '../../core/constants.dart';
import '../../core/storage.dart';
import '../../core/theme.dart';

class IdentityInfoScreen extends StatefulWidget {
  const IdentityInfoScreen({super.key});

  @override
  State<IdentityInfoScreen> createState() => _IdentityInfoScreenState();
}

class _IdentityInfoScreenState extends State<IdentityInfoScreen> {
  Map<String, dynamic>? _user;

  @override
  void initState() {
    super.initState();
    ActivityTracker.track(
      eventKey: 'identity_info_view',
      screenKey: 'identity_info',
      screenTitle: 'اطلاعات هویتی',
    );
    _loadData();
  }

  Future<void> _loadData() async {
    final userJson = await AppStorage.getUserJson();
    if (userJson != null) {
      setState(() {
        _user = jsonDecode(userJson)['user'];
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatarKey = _user?['avatar_key'];
    final avatarUrl = avatarKey != null ? AppConstants.fixUrl(avatarKey) : '';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(title: const Text('اطلاعات هویتی'), centerTitle: true),
      body: _user == null
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  // عکس پروفایل
                  Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: AppTheme.primary.withOpacity(0.1),
                      backgroundImage: avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: avatarUrl.isEmpty
                          ? const Icon(
                              Icons.person,
                              size: 50,
                              color: AppTheme.primary,
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // فیلدهای فقط خواندنی
                  _buildReadOnlyField(
                    'نام و نام خانوادگی',
                    _user?['full_name'] ?? '---',
                    Icons.person_outline,
                  ),
                  _buildReadOnlyField(
                    'شماره موبایل',
                    _user?['phone'] ?? '---',
                    Icons.phone_android_rounded,
                  ),
                  _buildReadOnlyField(
                    'کد ملی',
                    _user?['code_meli'] ?? '---',
                    Icons.credit_card_rounded,
                  ),
                  _buildReadOnlyField(
                    'تاریخ تولد',
                    _user?['birth_date'] ?? '---',
                    Icons.calendar_month_rounded,
                  ),

                  const SizedBox(height: 24),

                  // جعبه راهنما برای ارسال پیام
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.blue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'نیاز به ویرایش اطلاعات دارید؟',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.blue,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'به منظور حفظ امنیت حساب کاربری، تغییر اطلاعات هویتی امکان‌پذیر نیست. در صورت نیاز به ویرایش (مانند تغییر عکس یا اصلاح نام)، لطفاً از طریق بخش پشتیبانی به کارشناسان ما پیام ارسال نمایید.',
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.5,
                            color: Colors.black87,
                          ),
                          textAlign: TextAlign.justify,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => context.push('/support'),
                            icon: const Icon(Icons.support_agent_rounded),
                            label: const Text('ثبت پیام پشتیبانی'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Icon(icon, color: Colors.grey.shade400, size: 20),
                const SizedBox(width: 12),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.black87,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.lock_outline_rounded,
                  color: Colors.grey,
                  size: 16,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
