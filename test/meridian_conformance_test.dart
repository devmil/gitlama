import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'support/meridian_finders.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/widgets/author_avatar.dart';
import 'package:gitlama/widgets/gitlama_compass.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/gitlama_layout.dart';
import 'package:gitlama/widgets/gitlama_git_glyphs.dart';

Future<void> pumpMeridian(
  WidgetTester tester,
  Widget widget, {
  Brightness brightness = Brightness.light,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildAppTheme(brightness),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: widget)),
    ),
  );
  await tester.pump(MeridianDurations.hover);
}

BoxDecoration decorationOf<T extends Widget>(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(T),
    matching: find.byType(AnimatedContainer),
  );
  return tester.widget<AnimatedContainer>(finder.first).decoration!
      as BoxDecoration;
}

/// A fill as painted: any colour at zero alpha is no fill. Meridian fades
/// hover fills from the target colour at zero alpha instead of transparent
/// black, so the hue of an invisible fill varies.
int painted(Color color) => color.a == 0 ? 0 : color.toARGB32();

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final colors = brightness == Brightness.light
        ? gitlamaColors(Brightness.light)
        : gitlamaColors(Brightness.dark);
    testWidgets(
      'compass opens details and paints repository state in $brightness',
      (tester) async {
        var opened = 0;
        Widget compass({String? operation}) => GitLamaCompass(
          repository: 'GitLama',
          branch: 'main',
          ahead: 2,
          behind: 1,
          dirty: 3,
          conflicts: 1,
          operation: operation,
          progress: operation == null ? null : .5,
          onShowDetails: () => opened += 1,
        );
        await pumpMeridian(tester, compass(), brightness: brightness);
        expect(
          tester.getSize(find.byType(GitLamaCompass)).height,
          GitLamaLayout.compassHeight,
        );
        final pill = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(GitLamaCompass),
                matching: find.byType(Container),
              )
              .first,
        );
        final decoration = pill.decoration! as BoxDecoration;
        expect(decoration.color, colors.pane);
        expect(
          decoration.borderRadius,
          BorderRadius.circular(MeridianRadiusScale.pill),
        );
        expect(find.text('1 conflict'), findsOneWidget);
        expect(find.byType(MeridianProgressBar), findsNothing);
        await tester.tap(find.byType(GitLamaCompass));
        expect(opened, 1);
        await pumpMeridian(
          tester,
          compass(operation: 'Fetching…'),
          brightness: brightness,
        );
        // The state swaps out for the operation with a rise (NM-01).
        await tester.pump(MeridianDurations.exit);
        expect(find.byType(MeridianProgressBar), findsOneWidget);
        expect(find.text('1 conflict'), findsNothing);
        await pumpMeridian(
          tester,
          GitLamaCompass(
            repository: 'GitLama',
            branch: 'main',
            activeProgress: true,
            onShowDetails: () => opened += 1,
          ),
          brightness: brightness,
        );
        await tester.pump(MeridianDurations.exit);
        expect(find.byType(MeridianProgressBar), findsOneWidget);
        expect(find.text('Fetching…'), findsNothing);
      },
    );
    testWidgets('toolbar and Compass contents align in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianToolbarButton(
              label: 'Fetch',
              icon: 'fetch',
              onPressed: () {},
            ),
            const SizedBox(width: MeridianSpace.space4),
            GitLamaCompass(
              repository: 'GitLama',
              branch: 'main',
              onShowDetails: () {},
            ),
          ],
        ),
        brightness: brightness,
      );
      final button = tester.getRect(find.byType(MeridianToolbarButton));
      final icon = tester.getRect(
        find
            .descendant(
              of: find.byType(MeridianToolbarButton),
              matching: find.byType(MeridianIcon),
            )
            .first,
      );
      final caption = tester.getRect(find.text('Fetch'));
      expect(
        ((icon.top + caption.bottom) / 2 - button.center.dy).abs(),
        lessThanOrEqualTo(1),
      );
      final compass = tester.getRect(find.byType(GitLamaCompass));
      for (final label in ['GitLama', 'main']) {
        expect(
          (tester
                      .getRect(find.textContaining(label, findRichText: true))
                      .center
                      .dy -
                  compass.center.dy)
              .abs(),
          lessThanOrEqualTo(1),
        );
      }
    });
    testWidgets('buttons use Meridian fills and sizes in $brightness', (
      tester,
    ) async {
      for (final (variant, fill) in [
        (MeridianButtonVariant.primary, colors.accent),
        (MeridianButtonVariant.secondary, colors.pane),
        (MeridianButtonVariant.quiet, Colors.transparent),
        (MeridianButtonVariant.danger, colors.danger),
        (MeridianButtonVariant.dangerQuiet, Colors.transparent),
      ]) {
        await pumpMeridian(
          tester,
          MeridianButton(label: 'Action', variant: variant, onPressed: () {}),
          brightness: brightness,
        );
        expect(
          painted(decorationOf<MeridianButton>(tester).color!),
          painted(fill),
        );
        expect(
          tester.getSize(find.byType(MeridianButton)).height,
          MeridianSize.control,
        );
        expect(
          decorationOf<MeridianButton>(tester).borderRadius,
          BorderRadius.circular(gitlamaRadius.md),
        );
        expect(
          tester.widget<Text>(find.text('Action')).style?.fontSize,
          gitlamaText.label.fontSize,
        );
      }
      await pumpMeridian(
        tester,
        const MeridianButton(
          label: 'Disabled',
          onPressed: null,
          size: MeridianControlSize.small,
        ),
        brightness: brightness,
      );
      expect(
        tester.getSize(find.byType(MeridianButton)).height,
        moreOrLessEquals(gitlamaSmallButtonHeight, epsilon: 0.01),
      );
      expect(painted(decorationOf<MeridianButton>(tester).color!), 0);
    });

    testWidgets('secondary button and icon button paint hover in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        MeridianButton(label: 'Hover', onPressed: () {}),
        brightness: brightness,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer();
      await mouse.moveTo(tester.getCenter(find.byType(MeridianButton)));
      await tester.pump();
      await tester.pump(MeridianDurations.hover);
      expect(decorationOf<MeridianButton>(tester).color, colors.paneHover);
      await mouse.removePointer();
      await pumpMeridian(
        tester,
        MeridianIconButton(label: 'Refresh', icon: 'refresh', onPressed: () {}),
        brightness: brightness,
      );
      expect(
        tester.getSize(find.byType(MeridianIconButton)),
        const Size.square(MeridianSize.control),
      );
      expect(painted(decorationOf<MeridianIconButton>(tester).color!), 0);
      final iconMouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
      );
      await iconMouse.addPointer();
      await iconMouse.moveTo(tester.getCenter(find.byType(MeridianIconButton)));
      await tester.pump();
      await tester.pump(MeridianDurations.hover);
      expect(decorationOf<MeridianIconButton>(tester).color, colors.paneHover);
      await iconMouse.removePointer();
      await pumpMeridian(
        tester,
        const MeridianIconButton(
          label: 'Disabled',
          icon: 'refresh',
          onPressed: null,
          size: MeridianControlSize.small,
        ),
        brightness: brightness,
      );
      expect(
        tester.getSize(find.byType(MeridianIconButton)),
        const Size.square(MeridianSize.controlSm),
      );
    });

    testWidgets('toolbar, Kbd, count and glyph sizes in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianToolbarButton(
              label: 'Fetch',
              icon: 'refresh',
              badge: 3,
              onPressed: () {},
            ),
            const MeridianKbd(keys: ['Ctrl', 'F']),
            const MeridianCount(label: '2'),
            const GitLamaStatusGlyph('M'),
          ],
        ),
        brightness: brightness,
      );
      expect(
        tester.getSize(find.byType(MeridianToolbarButton)).height,
        MeridianLayout.toolbarButtonHeight,
      );
      expect(find.byType(MeridianCount), findsNWidgets(2));
      expect(
        tester.getSize(find.byType(MeridianKbd)).height,
        MeridianLayout.kbdHeight,
      );
      expect(
        tester.getSize(find.byType(GitLamaStatusGlyph)),
        const Size.square(GitLamaLayout.glyphSize),
      );
      final glyph = tester.widget<Container>(
        find.descendant(
          of: find.byType(GitLamaStatusGlyph),
          matching: find.byType(Container),
        ),
      );
      expect((glyph.decoration! as BoxDecoration).color, colors.warningBg);
      await pumpMeridian(
        tester,
        MeridianToolbarButton(
          label: 'Pull',
          icon: 'arrow-down',
          onPressed: () {},
        ),
        brightness: brightness,
      );
      expect(find.byType(MeridianCount), findsNothing);
      expect(
        tester.getSize(find.byType(MeridianToolbarButton)).height,
        MeridianLayout.toolbarButtonHeight,
      );
    });

    testWidgets(
      'avatar, spinner and progress use Meridian geometry in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AuthorAvatar(author: 'Ada Lovelace'),
              MeridianSpinner(),
              SizedBox(width: 100, child: MeridianProgressBar(value: 0.5)),
              MeridianHairline(),
            ],
          ),
          brightness: brightness,
        );
        expect(
          tester.getSize(find.byType(AuthorAvatar)),
          const Size.square(MeridianLayout.avatarSmall),
        );
        expect(
          tester.getSize(find.byType(MeridianSpinner)),
          const Size.square(MeridianLayout.spinnerSize),
        );
        expect(
          tester.getSize(find.byType(MeridianProgressBar)).height,
          MeridianLayout.progressHeight,
        );
        expect(
          tester.getSize(find.byType(MeridianHairline)).height,
          MeridianLayout.hairline,
        );
      },
    );
  }
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final colors = brightness == Brightness.light
        ? gitlamaColors(Brightness.light)
        : gitlamaColors(Brightness.dark);
    testWidgets(
      'every button variant paints hover, press and disabled in $brightness',
      (tester) async {
        for (final variant in MeridianButtonVariant.values) {
          await pumpMeridian(
            tester,
            MeridianButton(
              key: ValueKey(variant),
              label: 'Action',
              variant: variant,
              onPressed: () {},
            ),
            brightness: brightness,
          );
          final mouse = await tester.createGesture(
            kind: PointerDeviceKind.mouse,
          );
          await mouse.addPointer();
          await mouse.moveTo(tester.getCenter(find.byType(MeridianButton)));
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pump(MeridianDurations.hover);
          final hover = decorationOf<MeridianButton>(tester).color!;
          final expectedHover = switch (variant) {
            MeridianButtonVariant.primary => Color.alphaBlend(
              colors.onAccent.withValues(
                alpha: MeridianOpacity.primaryHoverOverlay,
              ),
              colors.accent,
            ),
            MeridianButtonVariant.secondary ||
            MeridianButtonVariant.quiet => colors.paneHover,
            MeridianButtonVariant.danger => Color.alphaBlend(
              colors.onDanger.withValues(
                alpha: MeridianOpacity.primaryHoverOverlay,
              ),
              colors.danger,
            ),
            MeridianButtonVariant.dangerQuiet => colors.dangerBg,
          };
          expect(hover.toARGB32(), expectedHover.toARGB32());
          final press = await tester.startGesture(
            tester.getCenter(find.byType(MeridianButton)),
          );
          await tester.pump(const Duration(milliseconds: 150));
          await tester.pump(MeridianDurations.hover);
          expect(
            decorationOf<MeridianButton>(tester).color!.toARGB32(),
            Color.alphaBlend(
              colors.ink.withValues(alpha: MeridianOpacity.pressedOverlay),
              expectedHover,
            ).toARGB32(),
          );
          await press.up();
          await mouse.removePointer();
          await pumpMeridian(
            tester,
            MeridianButton(
              key: ValueKey(variant),
              label: 'Action',
              variant: variant,
              onPressed: null,
            ),
            brightness: brightness,
          );
          expect(
            painted(decorationOf<MeridianButton>(tester).color!),
            painted(
              variant == MeridianButtonVariant.primary
                  ? colors.accentSoft
                  : Colors.transparent,
            ),
          );
        }
      },
    );

    testWidgets('icon button active, counts and status tones in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianIconButton(
              label: 'Active',
              icon: 'check',
              onPressed: () {},
              active: true,
            ),
            for (final tone in MeridianCountTone.values)
              MeridianCount(label: '3', tone: tone),
            for (final status in ['M', 'A', 'D', 'R', 'C', 'U', '?', '!'])
              GitLamaStatusGlyph(status),
            const AuthorAvatar(
              author: 'Ada Lovelace',
              size: MeridianLayout.avatarLarge,
            ),
          ],
        ),
        brightness: brightness,
      );
      expect(decorationOf<MeridianIconButton>(tester).color, colors.accentSoft);
      expect(
        tester.getSize(find.byType(AuthorAvatar)),
        const Size.square(MeridianLayout.avatarLarge),
      );
      final counts = tester
          .widgetList<MeridianCount>(find.byType(MeridianCount))
          .toList();
      expect(
        counts.map((count) => count.tone).toList(),
        MeridianCountTone.values,
      );
      for (final (tone, fill) in [
        (MeridianCountTone.neutral, colors.line),
        (MeridianCountTone.accent, colors.accent),
        (MeridianCountTone.attention, colors.attention),
        (MeridianCountTone.quiet, Colors.transparent),
      ]) {
        final count = find.byWidgetPredicate(
          (widget) => widget is MeridianCount && widget.tone == tone,
        );
        final decoration =
            tester
                    .widget<Container>(
                      find.descendant(
                        of: count,
                        matching: find.byType(Container),
                      ),
                    )
                    .decoration
                as BoxDecoration;
        expect(decoration.color, fill);
      }
      final glyphs = tester
          .widgetList<GitLamaStatusGlyph>(find.byType(GitLamaStatusGlyph))
          .toList();
      expect(glyphs.map((glyph) => glyph.status).toList(), [
        'M',
        'A',
        'D',
        'R',
        'C',
        'U',
        '?',
        '!',
      ]);
      for (final glyph in glyphs) {
        expect(
          tester.getSize(find.byWidget(glyph)),
          const Size.square(GitLamaLayout.glyphSize),
        );
      }
    });

    testWidgets(
      'sync badge and progress rule use token colours in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GitLamaSyncBadge(ahead: 3, behind: 6),
              SizedBox(width: 100, child: MeridianProgressBar(value: 0.5)),
            ],
          ),
          brightness: brightness,
        );
        expect(find.byTooltip('3 ahead, 6 behind'), findsOneWidget);
        // The value bar is an `accent` box (meridian_ui 0.9 paints it as a
        // positioned ColoredBox so the sweep can morph into it).
        expect(
          find.descendant(
            of: find.byType(MeridianProgressBar),
            matching: find.byWidgetPredicate(
              (widget) => widget is ColoredBox && widget.color == colors.accent,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'segmented track keeps geometry across selection in $brightness',
      (tester) async {
        var selected = 'One';
        await pumpMeridian(
          tester,
          StatefulBuilder(
            builder: (context, setState) => MeridianSegmented<String>(
              label: 'Mode',
              segments: [
                for (final value in const ['One', 'Two'])
                  MeridianSegment(value: value, label: value),
              ],
              value: selected,
              onChanged: (value) => setState(() => selected = value),
            ),
          ),
          brightness: brightness,
        );
        final track = find.byType(MeridianSegmented<String>);
        final firstSize = tester.getSize(track);
        expect(firstSize.height, MeridianSize.control);
        final trackDecoration =
            tester
                    .widget<Container>(
                      find
                          .descendant(
                            of: track,
                            matching: find.byType(Container),
                          )
                          .first,
                    )
                    .decoration
                as BoxDecoration;
        expect(trackDecoration.color, colors.paneAlt);
        expect(
          trackDecoration.borderRadius,
          BorderRadius.circular(gitlamaRadius.md),
        );
        await tester.tap(find.text('Two'));
        await tester.pump();
        expect(selected, 'Two');
        expect(tester.getSize(track), firstSize);
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await tester.pump();
        expect(selected, 'One');
      },
    );

    testWidgets(
      'field chrome uses rest, focus, error and search tokens in $brightness',
      (tester) async {
        final focus = FocusNode();
        addTearDown(focus.dispose);
        await pumpMeridian(
          tester,
          MeridianTextField(
            focusNode: focus,
            placeholder: 'Find',
            label: 'Query',
          ),
          brightness: brightness,
        );
        Finder chrome() => find
            .descendant(
              of: find.byType(MeridianTextField),
              matching: find.byType(Container),
            )
            .first;
        BoxDecoration decoration() =>
            tester.widget<Container>(chrome()).decoration! as BoxDecoration;
        expect(tester.getSize(chrome()).height, MeridianSize.control);
        expect(decoration().color, colors.pane);
        expect((decoration().border! as Border).top.color, colors.controlEdge);
        await tester.tap(find.byType(TextField));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isTrue);
        expect((decoration().border! as Border).top.color, colors.focus);
        await pumpMeridian(
          tester,
          const MeridianTextField(error: 'Required', placeholder: 'Find'),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(
          (decoration().border! as Border).top.color.toARGB32(),
          colors.danger.toARGB32(),
        );
        await pumpMeridian(
          tester,
          const MeridianTextField(
            variant: MeridianTextFieldVariant.search,
            placeholder: 'Find',
          ),
          brightness: brightness,
        );
        await tester.pumpAndSettle();
        expect(decoration().color, colors.paneAlt);
      },
    );

    testWidgets(
      'checkbox, switch and select use token geometry in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MeridianCheckbox(value: true, onChanged: (_) {}, label: 'Check'),
              MeridianSwitch(value: true, onChanged: (_) {}, label: 'Switch'),
              MeridianSelect<String>(
                value: 'One',
                values: const ['One', 'Two'],
                valueLabel: (value) => value,
                onChanged: (_) {},
              ),
            ],
          ),
          brightness: brightness,
        );
        expect(
          tester.getSize(_checkboxBox),
          const Size.square(MeridianLayout.checkboxSize),
        );
        expect(
          tester.getSize(find.byType(MeridianSelect<String>)).height,
          MeridianSize.control,
        );
        expect(
          tester.getSize(find.byType(MeridianSelect<String>)).width,
          greaterThanOrEqualTo(MeridianLayout.selectMinWidth),
        );
        final selectChrome = tester.widget<Container>(
          find
              .descendant(
                of: find.byType(MeridianSelect<String>),
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Container &&
                      widget.decoration is BoxDecoration &&
                      (widget.decoration! as BoxDecoration).border != null,
                ),
              )
              .first,
        );
        expect((selectChrome.decoration as BoxDecoration).color, colors.pane);
        final indicator = tester.widget<AnimatedContainer>(_checkboxFill);
        expect((indicator.decoration as BoxDecoration).color, colors.accent);
        final track = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(MeridianSwitch),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect((track.decoration as BoxDecoration).color, colors.accent);
      },
    );

    testWidgets('mixed and disabled checkbox and switch thumb in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MeridianCheckbox(
              value: null,
              onChanged: null,
              label: 'Mixed',
              tristate: true,
            ),
            MeridianSwitch(value: false, onChanged: null, label: 'Off'),
          ],
        ),
        brightness: brightness,
      );
      expect(
        find.byWidgetPredicate(
          (widget) => widget is MeridianIcon && widget.name == 'minus',
        ),
        findsOneWidget,
      );
      final mixedIndicator = tester.widget<AnimatedContainer>(_checkboxFill);
      final mixedDecoration = mixedIndicator.decoration as BoxDecoration;
      // Meridian fades a disabled checked box to ink-faint.
      expect(mixedDecoration.color, colors.inkFaint);
      final mixedBox = tester.widget<AnimatedContainer>(_checkboxBox);
      expect(
        ((mixedBox.decoration! as BoxDecoration).border! as Border).top.color,
        colors.inkFaint,
      );
      expect(
        tester.widget<Text>(find.text('Mixed')).style?.color,
        colors.inkFaint,
      );
      final track = tester.widget<AnimatedContainer>(
        find
            .descendant(
              of: find.byType(MeridianSwitch),
              matching: find.byType(AnimatedContainer),
            )
            .first,
      );
      // A disabled switch track is Meridian's disabled line.
      expect((track.decoration as BoxDecoration).color, colors.line);
      double thumbOffset() {
        final trackBox = find
            .descendant(
              of: find.byType(MeridianSwitch),
              matching: find.byType(AnimatedContainer),
            )
            .first;
        final thumbBox = find.descendant(
          of: trackBox,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Container &&
                widget.constraints ==
                    BoxConstraints.tight(
                      const Size.square(MeridianLayout.switchThumb),
                    ),
          ),
        );
        return tester.getRect(thumbBox).left - tester.getRect(trackBox).left;
      }

      expect(thumbOffset(), MeridianLayout.switchThumbInset);
      await pumpMeridian(
        tester,
        MeridianSwitch(value: true, onChanged: (_) {}, label: 'On'),
        brightness: brightness,
      );
      await tester.pumpAndSettle();
      expect(
        thumbOffset(),
        MeridianLayout.switchThumbInset + MeridianLayout.switchThumbTravel,
      );
    });

    testWidgets(
      'text area and selected segment use Meridian styles in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          const MeridianTextField(
            label: 'Description',
            placeholder: 'Write',
            monospace: true,
            minLines: 3,
            maxLines: 8,
          ),
          brightness: brightness,
        );
        expect(
          tester.widget<TextField>(find.byType(TextField)).style?.fontSize,
          gitlamaText.code.fontSize,
        );
        await pumpMeridian(
          tester,
          MeridianSegmented<String>(
            label: 'Mode',
            segments: [
              for (final value in const ['One', 'Two'])
                MeridianSegment(value: value, label: value),
            ],
            value: 'One',
            onChanged: (_) {},
          ),
          brightness: brightness,
        );
        // The selected segment's tile is the glide's indicator (MM-14).
        final selected = tester.widget<AnimatedContainer>(
          find
              .descendant(
                of: find.byType(MeridianGlide),
                matching: find.byType(AnimatedContainer),
              )
              .first,
        );
        expect((selected.decoration as BoxDecoration).color, colors.pane);
        expect(
          (selected.decoration as BoxDecoration).borderRadius,
          BorderRadius.circular(gitlamaRadius.sm),
        );
      },
    );
  }
  for (final brightness in [Brightness.light, Brightness.dark]) {
    final colors = brightness == Brightness.light
        ? gitlamaColors(Brightness.light)
        : gitlamaColors(Brightness.dark);
    testWidgets('island header, focus scope and selection in $brightness', (
      tester,
    ) async {
      await pumpMeridian(
        tester,
        MeridianIsland(
          title: 'History',
          child: MeridianListRow(title: 'Commit', selected: true, onTap: () {}),
        ),
        brightness: brightness,
      );
      final islandChrome = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(MeridianIsland),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).boxShadow != null,
              ),
            )
            .first,
      );
      expect((islandChrome.decoration as BoxDecoration).color, colors.pane);
      expect(
        (islandChrome.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(gitlamaRadius.lg),
      );
      expect(
        tester
            .getSize(
              find
                  .ancestor(
                    of: find.text('History'),
                    matching: find.byType(SizedBox),
                  )
                  .first,
            )
            .height,
        MeridianSize.islandHeader,
      );
      expect(
        MeridianSurfaceScope.maybeOf(
          tester.element(find.text('Commit')),
        )!.focused,
        isFalse,
      );
      expect(
        meridianSelectionFill(tester.element(find.text('Commit'))),
        colors.accentSoft,
      );
      await tester.tap(find.text('Commit'));
      await tester.pump();
      expect(
        MeridianSurfaceScope.maybeOf(
          tester.element(find.text('Commit')),
        )!.focused,
        isTrue,
      );
      // GitLama's soft selection stays `accent-soft` with focus; the
      // island halo shows the focus.
      expect(
        meridianSelectionFill(tester.element(find.text('Commit'))),
        colors.accentSoft,
      );
    });

    testWidgets('banner fills and dialog chrome in $brightness', (
      tester,
    ) async {
      for (final (kind, fill) in [
        (MeridianBannerTone.info, colors.paneAlt),
        (MeridianBannerTone.warning, colors.warningBg),
        (MeridianBannerTone.attention, colors.attentionBg),
        (MeridianBannerTone.error, colors.dangerBg),
      ]) {
        await pumpMeridian(
          tester,
          MeridianBanner(message: 'Message', tone: kind),
          brightness: brightness,
        );
        // A tone change fades the fill over motion-layout (MM-66).
        await tester.pump(MeridianDurations.layout);
        final chrome = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(MeridianBanner),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        expect(
          (chrome.decoration as BoxDecoration).color!.toARGB32(),
          fill.toARGB32(),
        );
        expect((chrome.decoration as BoxDecoration).border, isNull);
      }
      await pumpMeridian(
        tester,
        const MeridianDialog(title: 'Question', content: Text('Answer')),
        brightness: brightness,
      );
      final chrome = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(MeridianDialog),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is DecoratedBox &&
                    widget.decoration is BoxDecoration &&
                    (widget.decoration as BoxDecoration).boxShadow?.length == 2,
              ),
            )
            .first,
      );
      expect(
        (chrome.decoration as BoxDecoration).color!.toARGB32(),
        colors.raised.toARGB32(),
      );
      expect(
        (chrome.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(gitlamaRadius.xl),
      );
      expect(
        tester.getSize(find.byWidget(chrome)).width,
        MeridianLayout.dialogWidth,
      );
      expect(
        tester
            .widget<Padding>(
              find
                  .descendant(
                    of: find.byWidget(chrome),
                    matching: find.byType(Padding),
                  )
                  .first,
            )
            .padding,
        const EdgeInsets.all(MeridianSpace.space7),
      );
    });

    testWidgets(
      'disclosure toggles and floating panel honors reduced motion in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          const MeridianDisclosure(title: 'Details', child: Text('Contents')),
          brightness: brightness,
        );
        expect(find.text('Contents'), findsNothing);
        await tester.tap(find.text('Details'));
        await tester.pump();
        expect(find.text('Contents'), findsOneWidget);
        expect(
          tester
              .widget<Semantics>(
                find
                    .descendant(
                      of: find.byType(MeridianDisclosure),
                      matching: find.byType(Semantics),
                    )
                    .first,
              )
              .properties
              .expanded,
          isTrue,
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildAppTheme(brightness),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: true),
              child: child!,
            ),
            home: Scaffold(
              body: Center(
                child: MeridianPanel(
                  title: 'Panel',
                  width: 300,
                  onClose: () {},
                  child: const Text('Contents'),
                ),
              ),
            ),
          ),
        );
        // Reduce motion: a fade of at most 100 ms and no movement.
        await tester.pump();
        await tester.pump(MeridianDurations.reducedFade);
        expect(
          tester
              .widget<FadeTransition>(
                find.descendant(
                  of: find.byType(MeridianPanel),
                  matching: find.byType(FadeTransition),
                ),
              )
              .opacity
              .value,
          1,
        );

        expect(tester.getSize(find.byType(MeridianPanel)).width, 300);
      },
    );
    testWidgets(
      'palette match stays readable on the soft selection in $brightness',
      (tester) async {
        await pumpMeridian(
          tester,
          MeridianSurfaceScope(
            focused: true,
            child: MeridianListRow(
              title: 'Rebase branch',
              match: 'reb',
              selected: true,
              onTap: () {},
            ),
          ),
          brightness: brightness,
        );
        final label = tester.widget<Text>(find.text('Rebase branch'));
        final spans = (label.textSpan! as TextSpan).children!;
        expect((spans.first as TextSpan).text, 'Reb');
        expect(
          (spans.first as TextSpan).style?.fontWeight,
          gitlamaText.bodyStrong.fontWeight,
        );
        // The soft selection keeps the normal inks: the match is `accent`.
        expect(
          (spans.first as TextSpan).style?.color?.toARGB32(),
          colors.accent.toARGB32(),
        );
        // The first painted fill in the row (the attention layer paints none
        // at rest).
        final row = tester
            .widgetList<DecoratedBox>(
              find.descendant(
                of: find.byType(MeridianListRow),
                matching: find.byType(DecoratedBox),
              ),
            )
            .firstWhere(
              (box) => (box.decoration as BoxDecoration).color != null,
            );
        expect((row.decoration as BoxDecoration).color, colors.accentSoft);
      },
    );
  }
}

/// The 16px box (with its edge) of the one MeridianCheckbox on screen.
final _checkboxBox = find.descendant(
  of: find.byType(MeridianCheckbox),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is AnimatedContainer &&
        (widget.decoration as BoxDecoration?)?.border != null,
  ),
);

/// The checked fill of that checkbox (meridian_ui 0.9 pops it in as its
/// own layer, MM-11).
final _checkboxFill = find.descendant(
  of: find.byType(MeridianCheckbox),
  matching: find.byWidgetPredicate(
    (widget) =>
        widget is AnimatedContainer &&
        widget.decoration is BoxDecoration &&
        (widget.decoration! as BoxDecoration).border == null,
  ),
);
