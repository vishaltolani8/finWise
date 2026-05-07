import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/finwise_mvp.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

class FinWiseLoginPage extends StatefulWidget {
  const FinWiseLoginPage({required this.onLoggedIn, super.key});

  final VoidCallback onLoggedIn;

  @override
  State<FinWiseLoginPage> createState() => _FinWiseLoginPageState();
}

class _FinWiseLoginPageState extends State<FinWiseLoginPage> {
  final TextEditingController emailController =
      TextEditingController(text: "demo@finwise.local");
  final TextEditingController passwordController = TextEditingController();
  bool obscurePassword = true;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> completeLogin({bool demo = false}) async {
    final String email = demo || emailController.text.trim().isEmpty
        ? "demo@finwise.local"
        : emailController.text.trim();

    await sharedPreferences.setBool(finWiseMockLoggedInKey, true);
    await sharedPreferences.setString(finWiseMockEmailKey, email);

    if (appStateSettings["hasOnboarded"] != true) {
      await updateSettings("hasOnboarded", true, updateGlobalState: false);
    }
    if ((appStateSettings["username"] ?? "").toString().trim().isEmpty) {
      await updateSettings("username", "FinWise User",
          pagesNeedingRefresh: [], updateGlobalState: false);
    }

    widget.onLoggedIn();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 24,
              vertical: 32,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.account_balance_wallet_rounded,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text: finWiseAppName,
                    fontSize: 36,
                    fontWeight: FontWeight.bold,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 8),
                  TextFont(
                    text: "Personal finance made simple",
                    fontSize: 16,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "textLight"),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 36),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: "Email",
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: passwordController,
                    obscureText: obscurePassword,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => completeLogin(),
                    decoration: InputDecoration(
                      labelText: "Password",
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        tooltip:
                            obscurePassword ? "Show password" : "Hide password",
                        onPressed: () {
                          setState(() {
                            obscurePassword = !obscurePassword;
                          });
                        },
                        icon: Icon(
                          obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  Button(
                    label: "Login",
                    onTap: () => completeLogin(),
                  ),
                  const SizedBox(height: 10),
                  TextButton(
                    onPressed: () => completeLogin(demo: true),
                    child: const Text("Continue as demo user"),
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text:
                        "This MVP uses local demo login only. Cloud login and sync are reserved for a later update.",
                    fontSize: 13,
                    textAlign: TextAlign.center,
                    textColor: getColor(context, "textLight"),
                    maxLines: 3,
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
