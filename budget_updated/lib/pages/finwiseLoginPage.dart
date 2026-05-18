import 'package:budget/colors.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/finwise_mvp.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/accountAndBackup.dart';
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
  bool isLoadingGoogle = false;
  bool isLoadingDemo = false;

  Future<void> completeDemoLogin() async {
    setState(() {
      isLoadingDemo = true;
    });
    try {
      await sharedPreferences.setBool(finWiseMockLoggedInKey, true);
      await sharedPreferences.setString(
          finWiseMockEmailKey, "demo@finwise.local");
      await sharedPreferences.setBool("firebaseAuthEnabled", false);
      if ((appStateSettings["username"] ?? "").toString().trim().isEmpty) {
        await updateSettings(
          "username",
          "FinWise User",
          pagesNeedingRefresh: [],
          updateGlobalState: false,
        );
      }
      widget.onLoggedIn();
    } finally {
      if (mounted) {
        setState(() {
          isLoadingDemo = false;
        });
      }
    }
  }

  Future<void> signInWithGoogle() async {
    setState(() {
      isLoadingGoogle = true;
    });

    try {
      final bool signedIn = await signInGoogle(
        context: context,
        waitForCompletion: false,
        silentSignIn: false,
      );
      if (signedIn) {
        widget.onLoggedIn();
      }
    } catch (error) {
      print("Google Sign-In Error: $error");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Could not sign in with Google: $error"),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          isLoadingGoogle = false;
        });
      }
    }
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
                  _GoogleButton(
                    isLoading: isLoadingGoogle,
                    onTap: isLoadingGoogle ? null : signInWithGoogle,
                  ),
                  const SizedBox(height: 14),
                  Button(
                    label: isLoadingDemo
                        ? "Starting demo..."
                        : "Continue as demo user",
                    onTap: isLoadingDemo ? () {} : completeDemoLogin,
                  ),
                  const SizedBox(height: 18),
                  TextFont(
                    text:
                        "Google sign-in saves your PKR budget data with Drive backup and sync.",
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

class _GoogleButton extends StatelessWidget {
  const _GoogleButton({required this.isLoading, required this.onTap});

  final bool isLoading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.outline),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  )
                else
                  Icon(
                    Icons.g_mobiledata_rounded,
                    size: 28,
                    color: colorScheme.onSurface,
                  ),
                const SizedBox(width: 12),
                TextFont(
                  text: "Continue with Google",
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
