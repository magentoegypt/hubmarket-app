import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/shell/hub_scaffold.dart';
import '../../../../app/routes.dart';
import '../../../../app/theme/app_colors.dart';
import '../../../../core/app_info.dart';
import '../../../../core/config/store_contact.dart';
import '../../../../core/util/launch.dart';
import '../../../../core/widgets/brand_logo.dart';
import '../../../../core/widgets/social_icon.dart';
import '../../../../core/widgets/hub_back_button.dart';
import '../../../../l10n/l10n.dart';

/// About Hub Market — brand intro, company + contact details, social links,
/// accepted payment methods, and the app version. Contact details + social
/// links come from admin config ([storeContactProvider]). Reached from
/// Account → About Hub Market.
class AboutScreen extends ConsumerWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final c = ref.watch(storeContactProvider);
    final version = ref
        .watch(appVersionProvider)
        .maybeWhen(data: (v) => v, orElse: () => null);

    return HubScaffold(
      currentTab: AppTab.account,
      appBar: AppBar(
        centerTitle: true,
        leading: const HubBackButton(),
        title: Text(l10n.accountAbout),
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          const SizedBox(height: 28),
          const Center(child: BrandLogo(height: 54)),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              l10n.footerTagline,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, height: 1.4),
            ),
          ),
          const SizedBox(height: 24),

          // About paragraph.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              l10n.aboutBody,
              style: const TextStyle(
                color: AppColors.inkHeading,
                height: 1.55,
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Company + contact card.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.borderDefault),
              ),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        c.company,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                          color: AppColors.inkHeading,
                        ),
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderDefault),
                  _InfoRow(
                    icon: Icons.location_on_outlined,
                    text: c.address,
                    onTap: () => _open(
                      context,
                      Uri.parse(
                        'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(c.address)}',
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.borderDefault),
                  _InfoRow(
                    icon: Icons.call_outlined,
                    text: c.phoneDisplay,
                    onTap: () =>
                        _open(context, Uri(scheme: 'tel', path: c.phone)),
                  ),
                  const Divider(height: 1, color: AppColors.borderDefault),
                  _InfoRow(
                    icon: Icons.chat_outlined,
                    text: 'WhatsApp',
                    onTap: () => _open(context, Uri.parse(c.whatsapp)),
                  ),
                  const Divider(height: 1, color: AppColors.borderDefault),
                  _InfoRow(
                    icon: Icons.mail_outline,
                    text: c.email,
                    onTap: () => _open(context, mailtoUri(c.email)),
                  ),
                  if (c.hours.isNotEmpty) ...[
                    const Divider(height: 1, color: AppColors.borderDefault),
                    _InfoRow(icon: Icons.schedule_outlined, text: c.hours),
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Follow us — admin-configured social links (hidden when none set).
          if (c.socials.isNotEmpty) ...[
            _SectionLabel(l10n.aboutFollowUs),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  for (final s in c.socials)
                    _Social(
                      socialIconWidget(
                        s.key,
                        size: 19,
                        color: AppColors.brandPrimary,
                      ),
                      () => _open(context, Uri.parse(s.url)),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],

          // We accept.
          _SectionLabel(l10n.aboutWeAccept),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: _PaymentBadges(),
          ),
          const SizedBox(height: 28),

          // Version + copyright.
          Center(
            child: Text(
              version == null ? '' : '${l10n.versionLabel} $version',
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              l10n.footerRights,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.inkMuted, fontSize: 12),
            ),
          ),
          const SizedBox(height: 28),
        ],
      ),
    );
  }

  Future<void> _open(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    if (!await launchExternalUri(uri)) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.errorGeneric)));
    }
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 16, 12),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 15,
        color: AppColors.inkHeading,
      ),
    ),
  );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.text, this.onTap});
  final IconData icon;
  final String text;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: AppColors.brandPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: AppColors.inkHeading,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Blush circular social button (light surface).
class _Social extends StatelessWidget {
  const _Social(this.child, this.onTap);
  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 12),
    child: InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          color: AppColors.surfaceTint,
          shape: BoxShape.circle,
        ),
        child: child,
      ),
    ),
  );
}

/// Accepted payment marks (Visa · Mastercard · tabby · Cash on delivery).
class _PaymentBadges extends StatelessWidget {
  const _PaymentBadges();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: const [
        _PayCard(
          child: Text(
            'VISA',
            style: TextStyle(
              fontStyle: FontStyle.italic,
              fontWeight: FontWeight.w900,
              fontSize: 13,
              letterSpacing: 0.5,
              color: Color(0xFF1A1F71),
            ),
          ),
        ),
        _PayCard(child: _MastercardMark()),
        _PayCard(
          color: Color(0xFF3BE6C4),
          child: Text(
            'tabby',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 13,
              color: Color(0xFF1F2937),
            ),
          ),
        ),
        _PayCard(
          child: Icon(
            Icons.payments_outlined,
            size: 20,
            color: AppColors.success,
          ),
        ),
      ],
    );
  }
}

class _PayCard extends StatelessWidget {
  const _PayCard({required this.child, this.color});
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 34,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: color ?? Colors.white,
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: AppColors.borderDefault),
    ),
    child: child,
  );
}

class _MastercardMark extends StatelessWidget {
  const _MastercardMark();

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 30,
    height: 18,
    child: Stack(
      children: [
        const Positioned(left: 0, child: _Circle(Color(0xFFEB001B))),
        Positioned(
          right: 0,
          child: _Circle(const Color(0xFFF79E1B).withValues(alpha: 0.85)),
        ),
      ],
    ),
  );
}

class _Circle extends StatelessWidget {
  const _Circle(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 18,
    height: 18,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}
