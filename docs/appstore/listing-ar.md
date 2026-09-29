# App Store listing copy — Arabic (v1.0.0)

Paste-ready copy for the **Arabic** localization in App Store Connect. Pair it
with the `ar-*` screenshot set (RTL) — App Store Connect keeps screenshots per
localization, so the Arabic listing needs its own upload.

This is a localization, not a literal translation of `listing-en.md`: the
phrasing follows how UAE shoppers actually search, and the keyword list is
built from Arabic search terms rather than transliterated English ones.

Product counts match the English listing and come from live category counts —
see the note at the bottom of `listing-en.md`.

---

## Subtitle (30 max)

> عطور ومكياج وعناية بالبشرة

`26 chars`

---

## Promotional Text (170 max)

Editable any time without submitting a new build.

> تسوّق أكثر من 1700 عطر، مع العناية بالبشرة والمكياج والعناية بالشعر. وصل حديثاً كل أسبوع، والأكثر مبيعاً، وعروض يومية — مع التوصيل في جميع أنحاء الإمارات.

`154 chars`

---

## Keywords (100 max, comma-separated, no spaces)

> عطور,برفيوم,مكياج,تجميل,بشرة,سيروم,عود,كريم,شعر,مرطب,هدايا,دبي,الامارات

`71 chars`

Notes:
- Single words, not phrases — a space inside a keyword spends characters
  without adding a term.
- `الامارات` is written without the hamza on purpose: shoppers type it that way,
  and Apple's keyword matching is literal.
- Don't repeat anything already in the app name or subtitle; those are indexed
  separately, so repeating them wastes the 100 characters.

---

## Description (4000 max)

> **زونزي — عطور ومنتجات تجميل وعناية بالبشرة، تصلك في جميع أنحاء الإمارات.**
>
> تصفّح أكثر من 2300 منتج من العلامات التي تعرفها، بأسعار بالدرهم الإماراتي
> وتجربة شراء مصمّمة للإمارات.
>
> **مجموعة عطور حقيقية**
> أكثر من 1700 عطر — أو دو بارفان وأو دو تواليت وبارفان للنساء والرجال. صفِّ
> النتائج حسب العلامة أو السعر أو التركيز لتصل إلى ما تبحث عنه بسرعة.
>
> **العناية بالبشرة والمكياج والشعر**
> سيرومات ومرطّبات وغسولات وعلاجات ضمن أكثر من 475 منتجاً للعناية بالبشرة،
> إضافة إلى المكياج ومجموعة متنامية للعناية بالشعر.
>
> **ابحث بسرعة**
> - ابحث في المتجر كامل حسب المنتج أو العلامة التجارية
> - تصفّح حسب الفئة، أو انتقل مباشرة إلى العلامة من دليل العلامات الأبجدي
> - رتّب وصفِّ أي قائمة حسب السعر أو التقييم أو نسبة الخصم
> - وصل حديثاً والأكثر مبيعاً، مع تحدّث المخزون
> - عروض اليوم لفترة محدودة
>
> **صفحات منتجات بتفاصيل تهمّك**
> معرض صور كامل، ووصف المنتج، والأحجام والخيارات المتاحة، وحالة التوفّر، وتقييمات
> العملاء ومراجعاتهم حيثما وُجدت.
>
> **احفظ ما يعجبك**
> أضف المنتجات إلى المفضّلة وعُد إليها لاحقاً. المفضّلة وسلة التسوّق مرتبطتان
> بحسابك، فتجدهما بانتظارك عند التنقّل بين الأجهزة.
>
> **تجربة شراء مناسبة للإمارات**
> - الأسعار بالدرهم الإماراتي في كل مكان — دون مفاجآت في التحويل
> - دفتر عناوين يشمل الإمارات السبع
> - الدفع عند الاستلام متاح
> - توصيل مجاني للطلبات فوق 150 درهماً
> - تتبّع طلبك من التأكيد وحتى الوصول
>
> **بالعربية والإنجليزية**
> بدّل بين العربية والإنجليزية في أي وقت. التطبيق بالكامل — وليس النصوص فقط —
> ينتقل إلى تنسيق من اليمين إلى اليسار في العربية، مع عرض أسماء المنتجات والفئات
> والأسعار باللغة التي اخترتها.
>
> **حسابك**
> سجل الطلبات وتتبّعها، والعناوين المحفوظة، وإعدادات الملف الشخصي، وإشعارات
> تحديثات الطلب. يمكنك التصفّح وملء السلة دون حساب، وتسجيل الدخول عند إتمام
> الطلب. ويمكنك حذف حسابك نهائياً من داخل التطبيق في أي وقت.
>
> يشحن زونزي داخل دولة الإمارات العربية المتحدة.
>
> الدعم: [SUPPORT_URL]
> سياسة الخصوصية: [PRIVACY_URL]

`~1,850 chars` — well inside the 4,000 limit.

---

## Notes specific to the Arabic listing

- **App name.** App Store Connect allows a different display name per
  localization. Confirm with the owner whether the Arabic listing should show
  `زونزي` or keep the Latin `Zoonze`. The app's own display name stays `Zoonze`
  either way — this is store metadata only.
- **Numerals.** Western digits (1700, 2300, 150) are used throughout, matching
  the in-app decision recorded in `CLAUDE.md` §11.7 and the Figma.
- **Screenshots.** Use the `ar-*` set. They're genuinely RTL — mirrored nav bar,
  header and product page — so they won't look like flipped English shots.
- **Product names stay Latin.** The `eg_ar` store returns brand and product
  names in Latin script (e.g. "Gucci Bloom Parfum Women 100ml"), which is
  visible in the Arabic screenshots. That's catalog data, not an app issue, and
  is normal for beauty retail in the Gulf.
- **Same claims left out as the English listing** — no Tabby / instalments, and
  no card-brand specifics. See the closing section of `listing-en.md` for why.
