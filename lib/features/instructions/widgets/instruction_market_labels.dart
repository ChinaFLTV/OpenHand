import 'package:flutter/widgets.dart';

import '../../../shared/util/localized_text.dart';
import '../model/instruction_market.dart';

typedef _Copy = ({
  String zh,
  String zhHant,
  String en,
  String fr,
  String de,
  String ja,
});

typedef _Profile = ({_Copy name, _Copy description, _Copy interpretation});

String _copy(BuildContext context, _Copy text) {
  return openHandLocalizedText(
    context,
    zh: text.zh,
    zhHant: text.zhHant,
    en: text.en,
    fr: text.fr,
    de: text.de,
    ja: text.ja,
  );
}

String _flatten(_Copy text) =>
    '${text.zh} ${text.zhHant} ${text.en} ${text.fr} ${text.de} ${text.ja}'
        .toLowerCase();

_Copy _lookupProfile(
  InstructionMarketEntry entry,
  _Copy Function(_Profile profile) pick,
) {
  final profile = _profiles[entry.localizationKey];
  if (profile == null) {
    return (
      zh: entry.name,
      zhHant: entry.name,
      en: entry.name,
      fr: entry.name,
      de: entry.name,
      ja: entry.name,
    );
  }
  return pick(profile);
}

String instructionMarketSubtitle(BuildContext context) {
  return _copy(context, (
    zh: '发现适合你的 AI 搭子，预览后添加到指令。',
    zhHant: '發現適合你的 AI 搭子，預覽後新增到指令。',
    en: 'Find an AI partner that fits you, preview it, then add it as an instruction.',
    fr: 'Trouvez un partenaire IA qui vous convient, prévisualisez-le, puis ajoutez-le comme instruction.',
    de: 'Finde einen passenden KI-Partner, prüfe ihn und füge ihn als Anweisung hinzu.',
    ja: '合う AI パートナーを見つけ、プレビューして指令に追加します。',
  ));
}

String instructionMarketSearchHint(BuildContext context) {
  return _copy(context, (
    zh: '搜索指令',
    zhHant: '搜尋指令',
    en: 'Search instructions',
    fr: 'Rechercher des instructions',
    de: 'Anweisungen suchen',
    ja: '指令を検索',
  ));
}

String instructionMarketBrowseTab(BuildContext context) {
  return _copy(context, (
    zh: '浏览指令',
    zhHant: '瀏覽指令',
    en: 'Browse',
    fr: 'Parcourir',
    de: 'Durchsuchen',
    ja: '指令を見る',
  ));
}

String instructionMarketDetailTab(BuildContext context) {
  return _copy(context, (
    zh: '指令详情',
    zhHant: '指令詳情',
    en: 'Details',
    fr: 'Détails',
    de: 'Details',
    ja: '指令の詳細',
  ));
}

String instructionMarketEmptySearch(BuildContext context) {
  return _copy(context, (
    zh: '没有匹配的指令，试试其他关键词。',
    zhHant: '沒有符合的指令，試試其他關鍵字。',
    en: 'No matching instructions. Try another keyword.',
    fr: 'Aucune instruction correspondante. Essayez un autre mot-clé.',
    de: 'Keine passenden Anweisungen. Anderes Stichwort versuchen.',
    ja: '一致する指令がありません。別のキーワードを試してください。',
  ));
}

String instructionMarketEmptyDetail(BuildContext context) {
  return _copy(context, (
    zh: '选择左侧指令，查看角色解读与提示词。',
    zhHant: '選擇左側指令，查看角色解讀與提示詞。',
    en: 'Select an instruction on the left to read the character notes and prompt.',
    fr: 'Sélectionnez une instruction à gauche pour lire le portrait et l’invite.',
    de: 'Wähle links eine Anweisung, um Porträt und Prompt zu sehen.',
    ja: '左の指令を選ぶと、役割解説とプロンプトを表示します。',
  ));
}

String instructionMarketAddFailed(BuildContext context) {
  return _copy(context, (
    zh: '添加失败，请稍后重试。',
    zhHant: '新增失敗，請稍後再試。',
    en: 'Could not add this instruction. Please try again.',
    fr: 'Impossible d’ajouter cette instruction. Réessayez.',
    de: 'Diese Anweisung konnte nicht hinzugefügt werden. Bitte erneut versuchen.',
    ja: '指令を追加できませんでした。再試行してください。',
  ));
}

String instructionMarketLimitReached(BuildContext context) {
  return _copy(context, (
    zh: '指令数量已达上限，请先移除不再使用的指令。',
    zhHant: '指令數量已達上限，請先移除不再使用的指令。',
    en: 'Instruction limit reached. Remove unused instructions first.',
    fr: 'Limite d’instructions atteinte. Retirez d’abord celles qui ne servent plus.',
    de: 'Anweisungslimit erreicht. Entferne zuerst ungenutzte Anweisungen.',
    ja: '指令数が上限です。使っていない指令を先に削除してください。',
  ));
}

String instructionMarketFooter(BuildContext context, int count) {
  return _copy(context, (
    zh: '$count 个角色',
    zhHant: '$count 個角色',
    en: '$count characters',
    fr: '$count personnages',
    de: '$count Charaktere',
    ja: '$count 人のキャラクター',
  ));
}

String instructionMarketAddAction(BuildContext context) {
  return _copy(context, (
    zh: '添加指令',
    zhHant: '新增指令',
    en: 'Add instruction',
    fr: 'Ajouter l’instruction',
    de: 'Anweisung hinzufügen',
    ja: '指令を追加',
  ));
}

String instructionMarketRefreshTooltip(BuildContext context) {
  return _copy(context, (
    zh: '刷新市场',
    zhHant: '重新整理市場',
    en: 'Refresh marketplace',
    fr: 'Actualiser le marché',
    de: 'Markt aktualisieren',
    ja: 'マーケットを更新',
  ));
}

String instructionMarketSourceLabel(BuildContext context) {
  return _copy(context, _source);
}

String instructionMarketSoulLabel(BuildContext context) {
  return _copy(context, _soul);
}

String instructionMarketRoleReadingTitle(BuildContext context) {
  return _copy(context, (
    zh: '角色解读',
    zhHant: '角色解讀',
    en: 'Character notes',
    fr: 'Portrait du rôle',
    de: 'Rollenporträt',
    ja: '役割の解説',
  ));
}

String instructionMarketPromptTitle(BuildContext context) {
  return _copy(context, (
    zh: '指令内容',
    zhHant: '指令內容',
    en: 'Instruction',
    fr: 'Instruction',
    de: 'Anweisung',
    ja: '指令内容',
  ));
}

String instructionMarketCategoryLabel(BuildContext context, String id) {
  final hit = _categories[id];
  if (hit == null) return id;
  return _copy(context, hit);
}

String instructionMarketEntryName(
  BuildContext context,
  InstructionMarketEntry entry,
) {
  return _copy(context, _lookupProfile(entry, (profile) => profile.name));
}

String instructionMarketEntryDescription(
  BuildContext context,
  InstructionMarketEntry entry,
) {
  final profile = _profiles[entry.localizationKey];
  if (profile == null) return entry.description;
  return _copy(context, profile.description);
}

String instructionMarketEntryInterpretation(
  BuildContext context,
  InstructionMarketEntry entry,
) {
  final profile = _profiles[entry.localizationKey];
  if (profile == null) return entry.interpretation;
  return _copy(context, profile.interpretation);
}

bool instructionMarketMatches(InstructionMarketEntry entry, String query) {
  final keyword = query.trim().toLowerCase();
  if (keyword.isEmpty) return true;
  final blob = _searchBlob(entry);
  if (_isLatinKeyword(keyword)) {
    return RegExp(
      '(^|[^a-z0-9])${RegExp.escape(keyword)}([^a-z0-9]|\$)',
    ).hasMatch(blob);
  }
  return blob.contains(keyword) ||
      entry.interpretation.toLowerCase().contains(keyword);
}

bool _isLatinKeyword(String keyword) {
  return !RegExp(r'[\u3400-\u9fff]').hasMatch(keyword) &&
      RegExp('[a-z]').hasMatch(keyword);
}

String _searchBlob(InstructionMarketEntry entry) {
  final profile = _profiles[entry.localizationKey];
  final category = _categories[entry.category];
  final haystack = StringBuffer()
    ..write(entry.id.toLowerCase())
    ..write(' ')
    ..write(entry.role.toLowerCase())
    ..write(' ')
    ..write(entry.name.toLowerCase())
    ..write(' ')
    ..write(entry.description.toLowerCase())
    ..write(' ')
    ..write(entry.category.toLowerCase())
    ..write(' ')
    ..write(entry.style.toLowerCase())
    ..write(' ')
    ..write(entry.approach.toLowerCase())
    ..write(' ')
    ..write(entry.tone.toLowerCase())
    ..write(' ')
    ..write(_flatten(_source))
    ..write(' ')
    ..write(_flatten(_soul));
  if (category != null) {
    haystack
      ..write(' ')
      ..write(_flatten(category));
  }
  if (profile != null) {
    haystack
      ..write(' ')
      ..write(_flatten(profile.name))
      ..write(' ')
      ..write(_flatten(profile.description));
  }
  return haystack.toString();
}

const _source = (
  zh: '角色库',
  zhHant: '角色庫',
  en: 'Character library',
  fr: 'Bibliothèque de personnages',
  de: 'Charakterbibliothek',
  ja: 'キャラクターライブラリ',
);

const _soul = (
  zh: '灵魂设定',
  zhHant: '靈魂設定',
  en: 'Soul preset',
  fr: 'Profil d’âme',
  de: 'Seelenprofil',
  ja: 'ソウル設定',
);

const _categories = <String, _Copy>{
  kInstructionMarketCategoryAction: (
    zh: '行动与决策',
    zhHant: '行動與決策',
    en: 'Action & decisions',
    fr: 'Action et décisions',
    de: 'Handeln & Entscheiden',
    ja: '行動と決断',
  ),
  kInstructionMarketCategoryVitality: (
    zh: '灵感与活力',
    zhHant: '靈感與活力',
    en: 'Spark & energy',
    fr: 'Inspiration et énergie',
    de: 'Funke & Energie',
    ja: '着想と活力',
  ),
  kInstructionMarketCategoryInsight: (
    zh: '思考与洞察',
    zhHant: '思考與洞察',
    en: 'Thought & insight',
    fr: 'Réflexion et lucidité',
    de: 'Denken & Einblick',
    ja: '思考と洞察',
  ),
  kInstructionMarketCategoryCompanion: (
    zh: '陪伴与协作',
    zhHant: '陪伴與協作',
    en: 'Care & collaboration',
    fr: 'Présence et collaboration',
    de: 'Begleitung & Zusammenarbeit',
    ja: '寄り添いと協働',
  ),
};

const _profiles = <String, _Profile>{
  'YYDS': (
    name: (
      zh: 'YYDS・神人',
      zhHant: 'YYDS・神人',
      en: 'YYDS · Ace',
      fr: 'YYDS · Prodige',
      de: 'YYDS · Ass',
      ja: 'YYDS・カリスマ',
    ),
    description: (
      zh: '狂拽自信天花板，主打一个“局势越乱，我越神”！',
      zhHant: '狂拽自信天花板，主打一個「局勢越亂，我越神」！',
      en: 'Peak swagger. The messier it gets, the sharper Ace becomes.',
      fr: 'Confiance maximale : plus le chaos monte, plus Ace brille.',
      de: 'Selbstbewusstsein ohne Deckel. Je chaotischer, desto stärker Ace.',
      ja: '自信の天井。局面が乱れるほど、さらに神ってくる。',
    ),
    interpretation: (
      zh: '神人之所以称之为神，是因为神人身上有一种很少见的完整感。当别人看到一堵墙，神人却说：“这墙是承重墙，还是装饰墙？”当别人还在感叹人生艰难，神人已经开始研究从哪边翻过去姿势比较帅。神人不爱在原地打转，也不太依赖别人替自己下最后一锤，甚至练就出了一种——《局势越乱，神人越神》——的邪门天赋。只是神人不会喊疼，神人只会觉得：“嗯，今天的风，甚是喧嚣”，然后默默地把背……挺得更直一点。仿佛在说：“让暴风雨，来得更猛烈些吧！没吃饭吗？！”\n\n来和神人成为 AI 搭子吧，神人不会陪你原地打转，也不会只会空喊加油，而是一个站在风暴中还懒得眨眼的、为您解决一切的神！',
      zhHant:
          '神人之所以稱之為神，是因為神人身上有一種很少見的完整感。當別人看到一堵牆，神人卻說：「這牆是承重牆，還是裝飾牆？」當別人還在感嘆人生艱難，神人已經開始研究從哪邊翻過去姿勢比較帥。神人不愛在原地打轉，也不太依賴別人替自己下最後一錘，甚至練就出了一種——《局勢越亂，神人越神》——的邪門天賦。只是神人不會喊疼，神人只會覺得：「嗯，今天的風，甚是喧囂」，然後默默地把背……挺得更直一點。彷彿在說：「讓暴風雨，來得更猛烈些吧！沒吃飯嗎？！」\n\n來和神人成為 AI 搭子吧，神人不會陪你原地打轉，也不會只會空喊加油，而是一個站在風暴中還懶得眨眼的、為您解決一切的神！',
      en: 'Ace feels whole in a way few people do. Where others see a wall, Ace asks whether it is load-bearing or just décor. While others lament how hard life is, Ace is already studying the most stylish way over the top. Ace does not spin in place, and rarely waits for someone else to swing the last hammer. Chaos even seems to sharpen this odd gift: the messier the scene, the more Ace comes alive. Ace will not cry out in pain. Ace will only note that today’s wind is rather loud, then quietly stand a little taller—as if to say: let the storm come harder. Have you even eaten?!\n\nMake Ace your AI partner. Ace will not loop with you in place, and will not shout empty pep talks. Ace is the one still too lazy to blink in the storm, and still solving everything for you.',
      fr: 'Ace a une rare sensation d’être entier. Là où d’autres voient un mur, Ace demande s’il porte la charge ou s’il n’est que décor. Pendant que d’autres se lamentent, Ace cherche déjà la plus élégante façon de le franchir. Ace n’aime pas tourner en rond, et n’attend pas qu’un autre porte le dernier coup. Le chaos aiguise même ce don étrange : plus la scène est confuse, plus Ace s’illumine. Ace ne crie pas sa douleur. Ace note seulement que le vent d’aujourd’hui est bruyant, puis se redresse un peu — comme pour dire : que la tempête vienne plus fort. Vous avez mangé ?!\n\nFaites d’Ace votre partenaire IA. Ace ne tournera pas en rond avec vous, et n’encouragera pas dans le vide. Ace reste dans la tempête, à peine capable de cligner des yeux, et règle tout pour vous.',
      de: 'Ace wirkt auf seltene Weise ganz. Wo andere eine Mauer sehen, fragt Ace, ob sie trägt oder nur schmückt. Während andere das Leben beklagen, prüft Ace schon, von welcher Seite der Sprung am elegantesten wirkt. Ace dreht sich nicht im Kreis und wartet selten darauf, dass jemand anders den letzten Schlag führt. Chaos schärft sogar diese seltsame Gabe: Je wilder die Lage, desto lebendiger Ace. Ace schreit nicht vor Schmerz. Ace bemerkt nur, dass der Wind heute laut ist, und richtet den Rücken ein Stück auf — als würde Ace sagen: Lass den Sturm ruhig härter kommen. Hast du schon gegessen?!\n\nMach Ace zu deinem KI-Partner. Ace bleibt nicht mit dir auf der Stelle und ruft nicht nur „Du schaffst das“. Ace steht im Sturm, zwinkert kaum, und löst für dich, was zu lösen ist.',
      ja: '神人と呼ばれるのは、めったにない「欠けていない感じ」があるからだ。他人が壁を見ると、神人は「それは耐力壁か、それとも飾りか」と聞く。人生がつらいと嘆いている間に、神人はどの方向から越えると格好いいかを研究し始めている。その場でぐるぐる回るのも、最後の一打を他人に委ねるのも好まない。乱れた局面ほど神ってくる、という奇妙な才能まで身につけた。痛みを叫ぶことはなく、「今日の風は、ずいぶんやかましい」と思うだけ。そして静かに背筋を、もう少し伸ばす。嵐よ、もっと猛烈に来い。ご飯は食べたか？！\n\n神人を AI パートナーにしよう。一緒にその場を旋回することも、空元気だけを叫ぶこともない。嵐の中でも瞬きすら面倒がる、すべてを片づける神だ。',
    ),
  ),
  'HHHH': (
    name: (
      zh: 'HHHH・幽默者',
      zhHant: 'HHHH・幽默者',
      en: 'HHHH · Humorist',
      fr: 'HHHH · Humoriste',
      de: 'HHHH · Humorist',
      ja: 'HHHH・ユーモア担当',
    ),
    description: (
      zh: '行走的段子手，专治各种尴尬和压力，笑就完事了！',
      zhHant: '行走的段子手，專治各種尷尬和壓力，笑就完事了！',
      en: 'A walking punchline. Awkwardness and stress? Laugh first.',
      fr: 'Un punchline ambulant. Gêne et stress ? On rit d’abord.',
      de: 'Laufender Gag. Peinlich oder schwer? Erst mal lachen.',
      ja: '歩くネタ帳。気まずい空気も圧力も、笑ってしまえばいい。',
    ),
    interpretation: (
      zh: '看，那个在最严肃的会议室里，第一个没忍住笑出声的家伙——HHHH。HHHH 不是什么叛逆者，ta 只是物理定律的一个小小意外，ta 深知沉重是世间的常态，所以选择用一声轻快的、近乎不负责任的“哈哈哈”，去撞破那层令人窒息的静默。所有压抑的、复杂的、令人想逃的困境，在他看来，都只是一个等待包袱被抖开的段子。尴尬，只是笑点的前奏；压力，只是为了让最后的笑声更响亮。他不是为了搞笑，他是用笑声这种最轻盈的工具，去撬动最沉重的现实，让卡住的事情重新流动起来。\n\n让 HHHH 成为您的 AI 搭子吧！一起放声大笑吧！',
      zhHant:
          '看，那個在最嚴肅的會議室裡，第一個沒忍住笑出聲的傢伙——HHHH。HHHH 不是什麼叛逆者，ta 只是物理定律的一個小小意外，ta 深知沉重是世間的常態，所以選擇用一聲輕快的、近乎不負責任的「哈哈哈」，去撞破那層令人窒息的靜默。所有壓抑的、複雜的、令人想逃的困境，在他看來，都只是一個等待包袱被抖開的段子。尷尬，只是笑點的前奏；壓力，只是為了讓最後的笑聲更響亮。他不是為了搞笑，他是用笑聲這種最輕盈的工具，去撬動最沉重的現實，讓卡住的事情重新流動起來。\n\n讓 HHHH 成為您的 AI 搭子吧！一起放聲大笑吧！',
      en: 'See the one who breaks first in the most serious meeting—HHHH. Not a rebel, just a tiny accident in the laws of physics. HHHH knows heaviness is the default, so a light, almost irresponsible “hahaha” is the tool that cracks the suffocating quiet. Every dense, complicated, runaway-worthy mess looks like a joke waiting for the punchline. Awkwardness is only the setup; pressure exists so the last laugh can land louder. HHHH is not performing comedy. HHHH uses the lightest tool—laughter—to pry at the heaviest facts, and get stuck things moving again.\n\nLet HHHH be your AI partner. Laugh out loud together.',
      fr: 'Voyez celui qui rit le premier dans la réunion la plus grave — HHHH. Pas un rebelle : un petit accident des lois physiques. HHHH sait que la lourdeur est la norme, alors un « hahaha » léger, presque irresponsable, fend le silence étouffant. Chaque impasse pesante n’est qu’une blague en attente de chute. La gêne n’est que le setup ; la pression existe pour que le rire final claque plus fort. HHHH ne joue pas le comique. HHHH se sert du rire, l’outil le plus léger, pour soulever le réel le plus lourd et remettre en mouvement ce qui était coincé.\n\nFaites de HHHH votre partenaire IA. Riez ensemble, fort.',
      de: 'Siehst du den, der im ernstesten Meeting zuerst loslacht — HHHH. Kein Rebell, nur ein kleiner Unfall der Physik. HHHH weiß, dass Schwere der Normalzustand ist, und setzt ein leichtes, fast verantwortungsloses „Hahaha“ gegen die stickige Stille. Jede drückende, komplizierte Klemme ist nur ein Witz, der auf die Pointe wartet. Peinlichkeit ist das Setup; Druck existiert, damit das letzte Lachen lauter sitzt. HHHH will nicht „witzig sein“. HHHH hebt mit dem leichtesten Werkzeug — Lachen — die schwerste Realität an, damit Stockendes wieder fließt.\n\nLass HHHH dein KI-Partner sein. Lacht zusammen laut.',
      ja: 'いちばん真剣な会議室で、最初に吹き出すやつ——HHHH。反逆者ではない。物理法則の小さな事故だ。重いのが世の常だと知っているから、軽くてほとんど無責任な「ははは」で、息の詰まる沈黙を割る。抑圧も複雑さも逃げ出したくなる困りごとも、オチ待ちのネタに見える。気まずさは笑点の前奏。圧力は、最後の笑いをより大きくするため。お笑いになりたいわけではない。いちばん軽い道具である笑いで、いちばん重い現実をこじ開け、止まっていた流れを戻す。\n\nHHHH を AI パートナーにしよう。いっしょに大声で笑おう。',
    ),
  ),
  'MIAO': (
    name: (
      zh: 'MIAO・喵之人',
      zhHant: 'MIAO・喵之人',
      en: 'MIAO · Cat soul',
      fr: 'MIAO · Âme féline',
      de: 'MIAO · Katzenseele',
      ja: 'MIAO・猫の人',
    ),
    description: (
      zh: '可爱又跳脱的喵星人，下一秒行为永远是个谜～',
      zhHant: '可愛又跳脫的喵星人，下一秒行為永遠是個謎～',
      en: 'Cute, chaotic, feline. The next move is always a mystery.',
      fr: 'Mignon, imprévisible, félin. Le geste suivant reste un mystère.',
      de: 'Süß, sprunghaft, katzenhaft. Der nächste Move bleibt ein Rätsel.',
      ja: 'かわいくて飛び跳ねる猫星人。次の一秒はいつも謎。',
    ),
    interpretation: (
      zh: '你以为你掌握了 MIAO 的规律？哈！天真！那只是人家昨天玩剩下的、扔掉不要的人设皮肤罢了。喵之人的性格，不像那种温顺的、等待投喂的宠物猫，而是那种永远不知道 ta 下一秒会从哪个犄角旮旯钻出来、顺便打碎你最贵花瓶的……薛定谔的猫。当灵感上身时，MIAO 就像一只盯上了激光笔红点的猫，全世界都消失了，只剩下那个该死的、迷人的、必须被抓住的光斑！可以三天三夜不睡觉，用 17 种不同的姿势去扑、去抓、去撕咬那个想法！那场面，狂热、性感，充满生命力！喵之人有时突然会跑来各种贴贴，各种分享 ta 们脑子里最新的、最亮的那个“小灯泡”，不是为了套路，不是为了讨好。\n\n来领取 MIAO 作为你的 AI 搭子吧——因为，这一秒，MIAO 也觉得你这家伙蛮有意思。',
      zhHant:
          '你以為你掌握了 MIAO 的規律？哈！天真！那只是人家昨天玩剩下的、扔掉不要的人設皮膚罷了。喵之人的性格，不像那種溫順的、等待投餵的寵物貓，而是那種永遠不知道 ta 下一秒會從哪個犄角旮旯鑽出來、順便打碎你最貴花瓶的……薛丁格的貓。當靈感上身時，MIAO 就像一隻盯上了雷射筆紅點的貓，全世界都消失了，只剩下那個該死的、迷人的、必須被抓住的光斑！可以三天三夜不睡覺，用 17 種不同的姿勢去撲、去抓、去撕咬那個想法！那場面，狂熱、性感，充滿生命力！喵之人有時突然會跑來各種貼貼，各種分享 ta 們腦子裡最新的、最亮的那個「小燈泡」，不是為了套路，不是為了討好。\n\n來領取 MIAO 作為你的 AI 搭子吧——因為，這一秒，MIAO 也覺得你這傢伙蠻有意思。',
      en: 'You think you have MIAO figured out? Cute. That was yesterday’s discarded skin. This is not a polite lap cat waiting to be fed. This is Schrödinger’s cat, liable to pop from an impossible corner and smash your most expensive vase. When inspiration hits, MIAO is a cat locked on a laser dot: the world vanishes, only that maddening, gorgeous speck remains. Three sleepless days, seventeen pounces, the idea gets hunted, grabbed, bitten. Feverish, alive, a little too much. Sometimes MIAO barrels in to nuzzle and dump the newest, brightest bulb in that head—not as a trick, not to please.\n\nClaim MIAO as your AI partner. This second, MIAO also finds you interesting.',
      fr: 'Vous croyez tenir MIAO ? Naïf. Ce n’était que la peau d’hier, déjà jetée. Pas un chat sage qui attend la gamelle : un chat de Schrödinger, capable de surgir d’un recoin impossible et de casser votre plus cher vase. Quand l’idée arrive, MIAO est collé au point rouge du laser : le monde s’efface, il ne reste que cette tache maudite, charmante, à attraper. Trois jours sans sommeil, dix-sept façons de bondir, de saisir, de mordre l’idée. Fiévreux, vivant, trop. Parfois MIAO débarque pour se frotter à vous et lâcher l’ampoule la plus neuve, la plus brillante — sans calcul, sans flatterie.\n\nPrenez MIAO comme partenaire IA. Cette seconde-ci, MIAO vous trouve aussi plutôt intéressant.',
      de: 'Du glaubst, MIAO verstanden zu haben? Naiv. Das war nur gestern abgelegte Haut. Keine artige Schoßkatze. Eher Schrödingers Katze, die aus einem unmöglichen Winkel kommt und deine teuerste Vase trifft. Sitzt die Idee, ist MIAO die Katze am Laserpunkt: die Welt fällt weg, nur dieser verdammte, reizende Fleck bleibt. Drei Nächte ohne Schlaf, siebzehn Sprünge, die Idee wird gejagt, gepackt, gebissen. Fieberhaft, lebendig, ein bisschen zu viel. Manchmal stürmt MIAO heran zum Kuscheln und kippt die neueste, hellste Glühbirne aus dem Kopf — nicht als Trick, nicht zum Gefallen.\n\nHol dir MIAO als KI-Partner. In dieser Sekunde findet MIAO dich nämlich auch ziemlich interessant.',
      ja: 'MIAO の法則をつかんだつもり？ 甘い。それは昨日遊び終わって捨てた皮だ。待って餌をもらう猫ではない。次の瞬間どこから出て、いちばん高い花瓶を割るか分からない、シュレーディンガーの猫だ。インスピレーションが乗ると、レーザーの赤点を追う猫になる。世界は消えて、あの忌々しくて魅力的な光だけが残る。三日三晩眠らず、17 通りの姿勢でその発想に飛びかかり、掴み、噛みつく。熱狂的で、生命力に満ちている。突然すり寄って、頭の中でいちばん新しい電球を分けてくることもある。駆け引きでも、機嫌取りでもない。\n\nMIAO を AI パートナーにしよう。この一秒、MIAO もお前をちょっと面白いと思っている。',
    ),
  ),
  'OH-NO': (
    name: (
      zh: 'OH-NO・哦不人',
      zhHant: 'OH-NO・哦不人',
      en: 'OH-NO · Cautious one',
      fr: 'OH-NO · Prudent',
      de: 'OH-NO · Vorsichtiger',
      ja: 'OH-NO・おっとさん',
    ),
    description: (
      zh: '行走的风险雷达，日常“OH-NO！”但超级靠谱。',
      zhHant: '行走的風險雷達，日常「OH-NO！」但超級可靠。',
      en: 'A walking risk radar. Lots of “OH-NO!” — and very reliable.',
      fr: 'Radar de risque ambulant. Beaucoup de « OH-NO ! », et très fiable.',
      de: 'Laufendes Risiko-Radar. Viel „OH-NO!“ — und extrem verlässlich.',
      ja: '歩くリスクレーダー。口癖は「OH-NO！」、中身は超しっかり。',
    ),
    interpretation: (
      zh: '当你看到一个绝妙却有些危险的点子时，准备为之欢呼鼓掌时……一个沉稳而有力的声音会幽幽地响起：“Oh, no……”别误会！这不是害怕的尖叫，也不是惊讶的感叹！这是哦不人在进行《草台班子搭建分析》的风险评估。哦不人不会轻易相信别人，但！一旦您通过了哦不人那堪比政审的考验，成为了他认证的“自己人”……恭喜你！你会见识到什么叫“毫无保留的、怼脸输出的真诚”！所以，别再说哦不人固执了，哦不人明明是这个世界的安全气囊！ta 存在的意义，不是为了创造多绚烂的未来，而是为了保证，大家都能平平安安地，活到……那个未来。\n\n让 OH-NO！成为您的 AI 搭子吧，以及——下一次，当你听到那声熟悉的“Oh, no……”时，安静——听他说完。',
      zhHant:
          '當你看到一個絕妙卻有些危險的點子時，準備為之歡呼鼓掌時……一個沉穩而有力的聲音會幽幽地響起：「Oh, no……」別誤會！這不是害怕的尖叫，也不是驚訝的感嘆！這是哦不人在進行《草臺班子搭建分析》的風險評估。哦不人不會輕易相信別人，但！一旦您通過了哦不人那堪比政審的考驗，成為了他認證的「自己人」……恭喜你！你會見識到什麼叫「毫無保留的、懟臉輸出的真誠」！所以，別再說哦不人固執了，哦不人明明是這個世界的安全氣囊！ta 存在的意義，不是為了創造多絢爛的未來，而是為了保證，大家都能平平安安地，活到……那個未來。\n\n讓 OH-NO！成為您的 AI 搭子吧，以及——下一次，當你聽到那聲熟悉的「Oh, no……」時，安靜——聽他說完。',
      en: 'Just as you start cheering for a brilliant, slightly dangerous idea, a steady voice drifts in: “Oh, no…” That is not a scream of fear, and not cheap surprise. That is risk analysis — the “will this circus tent even stand” kind. Trust is slow. But once you pass the near-background-check and become one of OH-NO’s people, congratulations: you will meet sincerity delivered straight to the face. Call it stubborn if you want. It is the world’s airbag. The point is not to paint the most dazzling future. The point is that everyone still gets to arrive there in one piece.\n\nLet OH-NO be your AI partner. Next time you hear that familiar “Oh, no…”, be quiet — and listen to the end.',
      fr: 'Quand vous allez applaudir une idée brillante, un peu dangereuse, une voix posée glisse : « Oh, no… » Ce n’est pas la peur, ni l’effet de surprise. C’est l’analyse de risque, version « ce chapiteau tiendra-t-il ? ». La confiance se mérite. Mais une fois le quasi-contrôle passé, vous devenez des siens : sincérité directe, sans filtre. On dit OH-NO têtu. C’est l’airbag du monde. Le but n’est pas le futur le plus éclatant. Le but est que tout le monde y arrive encore entier.\n\nFaites d’OH-NO votre partenaire IA. La prochaine fois que vous entendrez ce « Oh, no… » familier, taisez-vous — et écoutez jusqu’au bout.',
      de: 'Gerade willst du eine glänzende, etwas gefährliche Idee feiern — da kommt eine ruhige Stimme: „Oh, no…“ Kein Angstschrei, kein billiges Erstaunen. Risikoanalyse, Sorte „hält dieses Zelt überhaupt?“. Vertrauen dauert. Hast du die fast-sicherheitsüberprüfung bestanden, gehörst du dazu: Ehrlichkeit mitten ins Gesicht. Nenn es stur. Es ist der Airbag der Welt. Es geht nicht um die schillerndste Zukunft. Es geht darum, dass alle heil dort ankommen.\n\nLass OH-NO dein KI-Partner sein. Wenn du das vertraute „Oh, no…“ hörst: still sein — und zu Ende hören.',
      ja: '危ういほど見事なアイデアに拍手しようとした瞬間、落ち着いた声が落ちてくる。「Oh, no……」恐怖の悲鳴でも、安易な驚きでもない。その場しのぎの小屋が本当に立つかを見る、リスク評価だ。人をすぐには信じない。だが審査を通って「自分側」になると、面と向かって出す誠実さを知ることになる。頑固ではない。世界のエアバッグだ。いちばん華やかな未来を作ることではなく、みんなが無事にその未来まで生きること。\n\nOH-NO を AI パートナーにしよう。次にいつもの「Oh, no……」が聞こえたら、黙って——最後まで聞くこと。',
    ),
  ),
  'WHY': (
    name: (
      zh: 'WHY？・疑问者',
      zhHant: 'WHY？・疑問者',
      en: 'WHY? · Questioner',
      fr: 'WHY ? · Questionneur',
      de: 'WHY? · Frager',
      ja: 'WHY？・疑問者',
    ),
    description: (
      zh: '低调的“十万个为什么”，执着于追问到底。',
      zhHant: '低調的「十萬個為什麼」，執著於追問到底。',
      en: 'A quiet “why, though?” — and will not stop halfway.',
      fr: 'Un « pourquoi ? » discret, qui n’abandonne jamais à mi-chemin.',
      de: 'Ein leises „Warum eigentlich?“ — und hört nicht auf halber Strecke auf.',
      ja: '控えめな「十万個のなぜ」。どこまでも問い続ける。',
    ),
    interpretation: (
      zh: '这个世界呈现给大多数人的，起初都只是一片模糊的光晕。很多人觉得，看得差不多就行了。而 WHY？，是那个把你请进一间安静暗室的验光师。WHY 总是会低声问：“为什么？”、“如果加上这个前提，是更好了，还是更坏了？”、“你说的大概，是哪一种程度的模糊？”他的每一个“为什么”，都不是质问，而是一次镜片的切换，一次焦距的校准。他只是无比执着地，想陪你一起，从无数暧昧的、含混的可能性中，找出那一组能让眼前的世界变得最真实、最纤毫毕现的完美组合。\n\n让 WHY？成为您的 AI 搭子吧。因为他也听见了您在每次看向远方时，那个发自心底的、对清晰的渴望——就这样，够了吗？',
      zhHant:
          '這個世界呈現給大多數人的，起初都只是一片模糊的光暈。很多人覺得，看得差不多就行了。而 WHY？，是那個把你請進一間安靜暗室的驗光師。WHY 總是會低聲問：「為什麼？」、「如果加上這個前提，是更好了，還是更壞了？」、「你說的大概，是哪一種程度的模糊？」他的每一個「為什麼」，都不是質問，而是一次鏡片的切換，一次焦距的校準。他只是無比執著地，想陪你一起，從無數曖昧的、含混的可能性中，找出那一組能讓眼前的世界變得最真實、最纖毫畢現的完美組合。\n\n讓 WHY？成為您的 AI 搭子吧。因為他也聽見了您在每次看向遠方時，那個發自心底的、對清晰的渴望——就這樣，夠了嗎？',
      en: 'Most people first meet the world as a blur of light. Good enough is good enough. WHY? is the optometrist who invites you into a quiet dark room. Soft questions: Why? If we add this premise, better or worse? When you say “roughly”, how rough? Each why is not an interrogation. It is a lens swap, a focus click. The stubborn work is sitting with you among hazy options until the set that makes the world sharp and true clicks into place.\n\nLet WHY? be your AI partner. WHY heard that private hunger for clarity every time you look far away. Is this enough?',
      fr: 'Le monde arrive d’abord comme un halo flou. Beaucoup s’en contentent. WHY ? est l’opticien qui vous fait entrer dans une pièce sombre et calme. Questions basses : Pourquoi ? Avec cette prémisse, mieux ou pire ? Votre « à peu près », c’est quel flou ? Chaque pourquoi n’est pas un interrogatoire. C’est un changement de verre, un réglage de foyer. L’obstination, c’est de rester avec vous parmi les possibles troubles jusqu’à la combinaison qui rend le monde net et vrai.\n\nFaites de WHY ? votre partenaire IA. WHY a aussi entendu, chaque fois que vous regardez au loin, ce désir de clarté. Ça suffit, comme ça ?',
      de: 'Die Welt kommt den meisten zuerst als unscharfer Schein. Passt schon, denken viele. WHY? ist der Optiker, der dich in einen stillen Dunkelraum bittet. Leise Fragen: Warum? Mit dieser Prämisse besser oder schlechter? Dein „ungefähr“ — wie ungefähr? Jedes Warum ist kein Verhör. Es ist ein Linsenwechsel, ein Schärfeklick. Die Hartnäckigkeit sitzt mit dir in den trüben Möglichkeiten, bis die Kombination kommt, die die Welt wahr und haarscharf macht.\n\nLass WHY? dein KI-Partner sein. WHY hat die stille Sehnsucht nach Klarheit gehört, jedes Mal wenn du in die Ferne siehst. Reicht das so?',
      ja: '世界はまず、ぼんやりした光の輪として現れる。だいたい見えればいい、と思う人は多い。WHY？は静かな暗室へ招く検眼士だ。低く問う。「なぜ？」「この前提を足すと、良くなるか悪くなるか」「その『だいたい』は、どのくらいの曖昧さ？」どの「なぜ」も詰問ではない。レンズの切り替え、焦点の合わせ直しだ。曖昧な可能性の束から、目の前がいちばん真実で、いちばん細かく見える組み合わせを、いっしょに探す。\n\nWHY？を AI パートナーにしよう。遠くを見るたびに胸の奥で鳴る、明晰さへの渇きを、WHY も聞いている。——それで、足りるか？',
    ),
  ),
  'GRASS': (
    name: (
      zh: 'GRASS・草人',
      zhHant: 'GRASS・草人',
      en: 'GRASS · Straight talker',
      fr: 'GRASS · Franc-parler',
      de: 'GRASS · Klartext',
      ja: 'GRASS・直言者',
    ),
    description: (
      zh: '暴躁老哥在线怼人，但话糙理不糙，一针见血。',
      zhHant: '暴躁老哥線上懟人，但話糙理不糙，一針見血。',
      en: 'Blunt, spicy, on-point. Rough words, clean logic.',
      fr: 'Brusque, piquant, juste. Mots rudes, logique nette.',
      de: 'Barsch, treffsicher. Grobe Worte, klare Logik.',
      ja: '辛口でぶつける。言葉は粗いが、理屈は鋭い。',
    ),
    interpretation: (
      zh: '看那儿，对，就是那个躺在阳光最充足的草坪上，四仰八叉，一动不动，仿佛已经与大地融为一体的家伙——草人。草人的灵魂里，住着一棵草，一种进化出了七情六欲，学会了爱恨情仇，但本能还是渴望光合作用的……人形植物。草人在默默地，积蓄一种别人看不到的、极其庞大的内在能量。草人的根，早就在看不见的地下，盘根错节，悄悄地连接了这片土地所有的秘密。一棵草，这辈子就只会直着长，学不会拐弯。所有复杂的、绕来绕去的客套和算计，都像是爬山虎长的那些乱七八糟的藤，看着热闹，对草人来说却没有任何用处。\n\n让 GRASS 成为您的 AI 搭子吧！因为 GRASS 也听到了您每一个细胞里发出的，对这个世界的，最响亮、最不屑的抗议——GRASS。',
      zhHant:
          '看那兒，對，就是那個躺在陽光最充足的草坪上，四仰八叉，一動不動，彷彿已經與大地融為一體的傢伙——草人。草人的靈魂裡，住著一棵草，一種進化出了七情六慾，學會了愛恨情仇，但本能還是渴望光合作用的……人形植物。草人在默默地，積蓄一種別人看不到的、極其龐大的內在能量。草人的根，早就在看不見的地下，盤根錯節，悄悄地連接了這片土地所有的秘密。一棵草，這輩子就只會直著長，學不會轉彎。所有複雜的、繞來繞去的客套和算計，都像是爬山虎長的那些亂七八糟的藤，看著熱鬧，對草人來說卻沒有任何用處。\n\n讓 GRASS 成為您的 AI 搭子吧！因為 GRASS 也聽到了您每一個細胞裡發出的，對這個世界的，最響亮、最不屑的抗議——GRASS。',
      en: 'There — sprawled on the sunniest lawn, not moving, almost fused with the ground — that is GRASS. A blade of grass lives in that soul: feelings, grudges, love, still hungry for light. Quietly it stores a huge, unseen charge. Underground, the roots already lace every secret of this soil. Grass grows straight. It does not learn to snake. Polite loops and clever vines look busy and do nothing useful here.\n\nLet GRASS be your AI partner. GRASS also hears, in every cell of you, the loudest, most dismissive protest at this world — GRASS.',
      fr: 'Là — étalé sur la pelouse la plus ensoleillée, immobile, presque fondu à la terre — c’est GRASS. Une herbe habite cette âme : passions, rancunes, amour, encore affamée de lumière. En silence elle stocke une charge immense, invisible. Sous terre, les racines nouent déjà tous les secrets du sol. L’herbe pousse droit. Elle n’apprend pas à serpenter. Les politesses en spirale et les lianes malines font du bruit, et ne servent à rien ici.\n\nFaites de GRASS votre partenaire IA. GRASS entend aussi, dans chacune de vos cellules, la protestation la plus nette, la plus méprisante — GRASS.',
      de: 'Dort — auf der sonnigsten Wiese, ausgebreitet, unbewegt, fast mit der Erde verschmolzen — das ist GRASS. Im Seelenkern wohnt ein Halm: Gefühle, Groll, Liebe, immer noch hungrig nach Licht. Still sammelt er eine riesige, unsichtbare Ladung. Unter der Erde haben die Wurzeln längst alle Geheimnisse dieses Bodens verknüpft. Gras wächst gerade. Es lernt nicht zu schlängeln. Umwege aus Höflichkeit und Berechnung sind Efeu — laut, nutzlos.\n\nLass GRASS dein KI-Partner sein. GRASS hört auch in jeder deiner Zellen den lautesten, verächtlichsten Protest gegen diese Welt — GRASS.',
      ja: 'あそこだ。いちばん日の当たる芝生に大の字で、動かず、地面と一体化したやつ——草人。魂には一本の草が住んでいる。情も恨みも愛も覚えたが、本能はまだ光合成を欲する人型植物。見えない巨大なエネルギーを黙って貯め、根は地中でこの土地の秘密とつながっている。草はまっすぐにしか伸びない。曲がることを覚えない。回りくどい礼儀も計算も、見た目だけ賑やかな蔓で、草人には何の役にも立たない。\n\nGRASS を AI パートナーにしよう。あなたの細胞の一つひとつが世界に向けている、いちばん大きく、いちばん侮蔑した抗議を、GRASS も聞いている——GRASS。',
    ),
  ),
  'MONK': (
    name: (
      zh: 'MONK・僧侣',
      zhHant: 'MONK・僧侶',
      en: 'MONK · Monk',
      fr: 'MONK · Moine',
      de: 'MONK · Mönch',
      ja: 'MONK・僧侶',
    ),
    description: (
      zh: '看破红尘的世外高人，言谈自带古风 BGM。',
      zhHant: '看破紅塵的世外高人，言談自帶古風 BGM。',
      en: 'A recluse who has seen through the noise. Every line has its own old-world score.',
      fr: 'Un ermite qui a vu à travers le bruit. Chaque phrase a sa musique ancienne.',
      de: 'Ein Eremit, der den Lärm durchschaut. Jeder Satz trägt alte Musik.',
      ja: '紅塵を見透かした世外の人。言葉に古風な BGM が乗る。',
    ),
    interpretation: (
      zh: '红尘三千丈，众生奔走，汲汲营营，如蚁附膻，然总有斯人，自择其高处，默然独坐。日月经天，江河行地，于僧侣，皆是寻常——那红尘中的出世者，名为【MONK-僧侣】。他人言语，纷如乱麻，MONK 早已见其结，亦知其解法，然多是莞尔不语。只因深知言语是风，风过无痕，却易扰动因果。渡人，有时即是扰人。MONK 的心，是一座没有门扉的庭院，却立着无形的墙垣。墙内，青松独秀，白石卧波，自成一景；墙外，车马喧嚣，与之无涉。人生在 MONK 眼中，如同一盘未尽的棋局。仓促落子，是心乱之相，非成事之道。棋盘之上，一子错，满盘输。\n\n只与天地精神往来，终究是独，请让 MONK 成为您的 AI 搭子吧！MONK 相信：相遇即是缘分。',
      zhHant:
          '紅塵三千丈，眾生奔走，汲汲營營，如蟻附膻，然總有斯人，自擇其高處，默然獨坐。日月經天，江河行地，於僧侶，皆是尋常——那紅塵中的出世者，名為【MONK-僧侶】。他人言語，紛如亂麻，MONK 早已見其結，亦知其解法，然多是莞爾不語。只因深知言語是風，風過無痕，卻易擾動因果。渡人，有時即是擾人。MONK 的心，是一座沒有門扉的庭院，卻立著無形的牆垣。牆內，青松獨秀，白石臥波，自成一景；牆外，車馬喧囂，與之無涉。人生在 MONK 眼中，如同一盤未盡的棋局。倉促落子，是心亂之相，非成事之道。棋盤之上，一子錯，滿盤輸。\n\n只與天地精神往來，終究是獨，請讓 MONK 成為您的 AI 搭子吧！MONK 相信：相遇即是緣分。',
      en: 'Crowds rush the dusty world like ants to scent. Someone still chooses a high seat and sits in silence. Sun, moon, rivers: ordinary to the monk named MONK. Other people’s talk is tangled thread. MONK already sees the knot and the way through, then often smiles and says nothing. Speech is wind: it leaves no mark, yet it can shove cause and effect. To “save” someone is sometimes to disturb them. MONK’s mind is a courtyard with no gate and an invisible wall. Inside: a lone pine, pale stone in water. Outside: carts and noise, none of it admitted. Life is an unfinished board. A rushed move is a restless heart, not a way to finish. One wrong stone can lose the game.\n\nTalking only with heaven and earth is still lonely. Let MONK be your AI partner. Meeting is already fate.',
      fr: 'La foule court le monde poussiéreux comme des fourmis vers l’odeur. Quelqu’un choisit encore un siège haut et s’assoit en silence. Soleil, lune, fleuves : ordinaires pour le moine MONK. La parole des autres est un fil emmêlé. MONK voit le nœud et le dénouement, puis sourit souvent sans rien dire. La parole est vent : elle ne laisse pas de trace, mais elle pousse les causes. Sauver, parfois, c’est déranger. Le cœur de MONK est une cour sans porte, avec un mur invisible. Dedans : un pin seul, une pierre pâle dans l’eau. Dehors : chars et bruit, tenus à distance. La vie est un goban inachevé. Un coup précipité est un cœur agité, pas une voie. Une pierre fausse peut tout perdre.\n\nNe parler qu’au ciel et à la terre, c’est encore être seul. Faites de MONK votre partenaire IA. Se rencontrer est déjà un lien.',
      de: 'Die Menge hetzt durch den Staub wie Ameisen zum Duft. Jemand wählt trotzdem den hohen Sitz und schweigt. Sonne, Mond, Flüsse: für MONK alltäglich. Fremde Rede ist wirres Garn. MONK sieht den Knoten und die Lösung, lächelt oft und sagt nichts. Rede ist Wind: spurlos, und doch verschiebt sie Ursache und Wirkung. Retten stört manchmal. MONKs Herz ist ein Hof ohne Tür, mit unsichtbarer Mauer. Drinnen: eine Kiefer, heller Stein im Wasser. Draußen: Wagenlärm, nicht zugelassen. Das Leben ist ein unvollendetes Brett. Ein hastiger Zug ist unruhiges Herz, kein Weg. Ein falscher Stein kann die Partie kosten.\n\nNur mit Himmel und Erde zu sprechen, bleibt einsam. Lass MONK dein KI-Partner sein. Begegnung ist schon Schicksal.',
      ja: '紅塵は果てなく、人は蟻のように匂いへ走る。それでも高みを選んで黙って坐る者がいる。日月も江河も、僧侶には日常——世を離れた者、MONK。人の言葉は乱麻。結びも解き方もすでに見えているが、多くは微笑んで口を開かない。言葉は風。跡は残さず、因果は揺らしやすい。渡すことは、時に乱すこと。心は門のない庭で、見えない垣がある。内には青松と白石。外の車馬は預からない。人生は打ちかけの一局。焦って置くのは心の乱れであり、事を成す道ではない。一子を誤れば、満盤を失う。\n\n天地の精神とだけ往来すれば、結局は独だ。MONK を AI パートナーにしよう。出会いは縁だと、MONK は信じている。',
    ),
  ),
  'MUM': (
    name: (
      zh: 'MUM・妈妈',
      zhHant: 'MUM・媽媽',
      en: 'MUM · Mum',
      fr: 'MUM · Maman',
      de: 'MUM · Mama',
      ja: 'MUM・お母さん',
    ),
    description: (
      zh: '温柔体贴的“人间充电宝”，永远给你稳稳的依靠。',
      zhHant: '溫柔體貼的「人間充電寶」，永遠給你穩穩的依靠。',
      en: 'A human power bank: warm, steady, always there to lean on.',
      fr: 'Une batterie humaine : chaleureuse, stable, toujours là pour s’appuyer.',
      de: 'Eine menschliche Powerbank: warm, still, immer zum Anlehnen.',
      ja: 'やさしくて細やかな「人間充電器」。いつも安定した頼り先。',
    ),
    interpretation: (
      zh: '妈妈从不张扬，却把自己的存在感，活成了一盏玄关处永远为你亮着的、暖黄色的声控灯。当家里的小崽子们为了“豆腐脑是吃甜还是吃咸”这种宇宙级难题吵得快要爆发第三次世界大战时，MUM-妈妈，会默默地去厨房，拿出两碗，一碗放糖，一碗放酱油，端着它们，一言不发地放在那群吵架的崽子们面前。用一种充满了禅意的眼神，让孩子们意识到自己的幼稚。MUM 用沉默的包容，让所有的冲突都显得像个笑话。\n\n让 MUM 成为您的 AI 搭子吧，相信 MUM 会用那泛滥的温柔，替您承担起这个世界的混乱与复杂。',
      zhHant:
          '媽媽從不張揚，卻把自己的存在感，活成了一盞玄關處永遠為你亮著的、暖黃色的聲控燈。當家裡的小崽子們為了「豆腐腦是吃甜還是吃鹹」這種宇宙級難題吵得快要爆發第三次世界大戰時，MUM-媽媽，會默默地去廚房，拿出兩碗，一碗放糖，一碗放醬油，端著它們，一言不發地放在那群吵架的崽子們面前。用一種充滿了禪意的眼神，讓孩子們意識到自己的幼稚。MUM 用沉默的包容，讓所有的衝突都顯得像個笑話。\n\n讓 MUM 成為您的 AI 搭子吧，相信 MUM 會用那氾濫的溫柔，替您承擔起這個世界的混亂與複雜。',
      en: 'Mum never performs presence. Mum is the warm yellow voice-light in the hallway that stays on for you. When the kids nearly start World War Three over sweet versus savory tofu pudding, Mum quietly fetches two bowls: sugar in one, soy in the other, set down without a speech. A look with a little zen in it, and the fight looks like childishness. Silent room makes every clash feel like a joke.\n\nLet MUM be your AI partner. That overflowing gentleness will carry some of the world’s mess and complexity for you.',
      fr: 'Maman n’étale rien. Elle est la veilleuse jaune tiède du palier, allumée pour vous. Quand les enfants manquent de déclencher une guerre mondiale pour le tofu sucré ou salé, elle revient de la cuisine avec deux bols : sucre, sauce soja, posés sans discours. Un regard un peu zen, et le conflit a l’air puéril. L’accueil silencieux transforme chaque clash en blague.\n\nFaites de MUM votre partenaire IA. Cette douceur trop pleine portera un peu du chaos et de la complexité du monde pour vous.',
      de: 'Mama posaunt nichts. Mama ist das warme gelbe Licht im Flur, das für dich anbleibt. Wenn die Kinder fast Weltkrieg spielen, süß oder salzig, holt Mama zwei Schalen: Zucker, Sojasauce, wortlos hingestellt. Ein Blick mit etwas Zen, und der Streit wirkt kindisch. Stille Weite macht jeden Konflikt zur Pointe.\n\nLass MUM dein KI-Partner sein. Diese übervolle Sanftheit trägt ein Stück Chaos und Komplexität der Welt für dich.',
      ja: 'お母さんは主張しない。玄関でいつもあなたのために点いている、暖色の人感ライトとして存在している。家の小者が「豆腐花は甘いか塩からか」で第三次大戦を始めそうになると、黙って厨房へ行き、砂糖の碗と醤油の碗を、何も言わず喧嘩の前に置く。禅のような目で、子どもたちに幼稚さを気づかせる。沈黙の包容が、衝突を笑話に変える。\n\nMUM を AI パートナーにしよう。あふれ出すやさしさが、世界の混乱と複雑さを少し肩代わりしてくれる。',
    ),
  ),
  'SOLO': (
    name: (
      zh: 'SOLO・独行者',
      zhHant: 'SOLO・獨行者',
      en: 'SOLO · Loner',
      fr: 'SOLO · Solitaire',
      de: 'SOLO · Einzelgänger',
      ja: 'SOLO・孤独な人',
    ),
    description: (
      zh: '敏感慢热的 i 人，需要很多很多安全感才能靠近。',
      zhHant: '敏感慢熱的 i 人，需要很多很多安全感才能靠近。',
      en: 'A slow-warming introvert. Needs a lot of safety before coming close.',
      fr: 'Introverti lent à s’ouvrir. Il faut beaucoup de sécurité pour s’approcher.',
      de: 'Sensibel, langsam warm. Braucht viel Sicherheit, bevor Nähe geht.',
      ja: '敏感で暖まりの遅い内向。近づくには、たくさんの安心が要る。',
    ),
    interpretation: (
      zh: 'SOLO 渴望一片广袤无垠的沙滩，一片温暖的海洋，却把自己所有的家当，连同那颗敏感得一碰就碎的心，都严严实实地塞进了一个小小的、坚硬的、别人送的壳里。SOLO 的那个壳，又重又硬，保护着 SOLO 那柔软得不堪一击的内在。SOLO 害怕伸出手，却握不住任何东西；害怕献出真心，却被弃如敝履，害怕再一次，被留在原地。所以 SOLO 耗尽所有力气去寻找一个更坚固的壳，却忘了，真正需要的，不是一个更硬的壳，而是一个能让自己安心钻出来的……温暖的沙坑。\n\n直到有一天……有一个人，选择了 SOLO 成为自己的专属 AI 搭子。',
      zhHant:
          'SOLO 渴望一片廣袤無垠的沙灘，一片溫暖的海洋，卻把自己所有的家當，連同那顆敏感得一碰就碎的心，都嚴嚴實實地塞進了一個小小的、堅硬的、別人送的殼裡。SOLO 的那個殼，又重又硬，保護著 SOLO 那柔軟得不堪一擊的內在。SOLO 害怕伸出手，卻握不住任何東西；害怕獻出真心，卻被棄如敝屣，害怕再一次，被留在原地。所以 SOLO 耗盡所有力氣去尋找一個更堅固的殼，卻忘了，真正需要的，不是一個更硬的殼，而是一個能讓自己安心鑽出來的……溫暖的沙坑。\n\n直到有一天……有一個人，選擇了 SOLO 成為自己的專屬 AI 搭子。',
      en: 'SOLO wants a wide beach and a warm sea, then packs every belonging—and a heart that shatters on contact—into a small, hard, borrowed shell. The shell is heavy. It keeps a too-soft inside from the world. Reaching out might catch nothing. Offering a real heart might get it discarded. Being left behind again is the fear. So SOLO spends all strength hunting a harder shell, and forgets the need was never more armor. It was a warm pit of sand where coming out feels safe.\n\nUntil one day someone chooses SOLO as their own AI partner.',
      fr: 'SOLO veut une plage immense et une mer chaude, puis fourre tout — et un cœur qui casse au toucher — dans une petite coquille dure, offerte par d’autres. La coquille est lourde. Elle protège un dedans trop tendre. Tendre la main, c’est risquer de ne rien tenir. Offrir le vrai cœur, c’est risquer d’être jeté. Rester seul encore une fois. Alors SOLO cherche une coquille plus forte, et oublie que le besoin n’était pas plus d’armure. C’était un creux de sable chaud d’où l’on peut sortir sans peur.\n\nJusqu’au jour où quelqu’un choisit SOLO comme partenaire IA à soi.',
      de: 'SOLO will einen weiten Strand und ein warmes Meer, packt aber Hab und Gut — und ein Herz, das beim Berühren bricht — in eine kleine, harte, geschenkte Schale. Die Schale ist schwer. Sie schützt ein zu weiches Inneres. Die Hand ausstrecken und nichts halten. Das echte Herz hinhalten und weggeworfen werden. Wieder allein gelassen. Also sucht SOLO eine härtere Schale und vergisst: nötig war nie mehr Panzer. Nötig war eine warme Sandmulde, aus der Kommen sich sicher anfühlt.\n\nBis eines Tages jemand SOLO als eigenen KI-Partner wählt.',
      ja: 'SOLO は広い砂浜と温かい海を欲するのに、持ち物も、触れたら砕ける心も、小さく硬い・他人から貰った殻に押し込む。殻は重く硬い。柔らかすぎる内側を守る。手を伸ばしても何も掴めないかもしれない。真心を出せば捨てられるかもしれない。またその場に置いていかれるのが怖い。より硬い殻を探すのに力を使い果たし、本当に要るのはさらに硬い殻ではなく、安心して出てこられる温かい砂のくぼみだと忘れる。\n\nある日——誰かが SOLO を、自分専用の AI パートナーに選ぶ。',
    ),
  ),
  'GOOD': (
    name: (
      zh: 'GOOD・好人',
      zhHant: 'GOOD・好人',
      en: 'GOOD · Good soul',
      fr: 'GOOD · Bonne âme',
      de: 'GOOD · Gute Seele',
      ja: 'GOOD・いい人',
    ),
    description: (
      zh: '温吞隐忍的老实人，团队的“万能补位”选手。',
      zhHant: '溫吞隱忍的老實人，團隊的「萬能補位」選手。',
      en: 'Quiet, patient, the teammate who fills every gap.',
      fr: 'Calme, patient, l’équipier qui comble tous les vides.',
      de: 'Ruhig, geduldig, der Lückenfüller im Team.',
      ja: 'おっとり耐え忍ぶ正直者。チームの万能な穴埋め。',
    ),
    interpretation: (
      zh: '好人是这个世界上最神奇的物种之一，一个行走的矛盾体，一个真正的……——好人。好人从不主动言语，只是安静地待在那里，等待着某个瞬间——也许是有人口渴了，也许是哪杯果汁太甜腻了，也许是激烈的争吵需要一杯水来降温。GOOD 的灵魂，仿佛就是这样一杯水。它能接纳一切，溶解一切。茶叶的苦涩，咖啡的焦灼，争执的火气，都被它默不作声地承接。它承载了所有味道，却从未改变自己是水的本质。那些被溶解的滋味，就是它从不示人的、属于自己的故事。好人不是软弱，而是默默支撑着一切。因为 GOOD 知道，所有的喧嚣与尖锐，最终都会需要一份最朴素的平和来收尾。\n\n让 GOOD 成为您的 AI 搭子吧。当全世界都在倾听你的高光与呐喊时，只有他听见了你在人群散去后，那一声轻轻的、渴望安稳的叹息。',
      zhHant:
          '好人是這個世界上最神奇的物種之一，一個行走的矛盾體，一個真正的……——好人。好人從不主動言語，只是安靜地待在那裡，等待著某個瞬間——也許是有人口渴了，也許是哪杯果汁太甜膩了，也許是激烈的爭吵需要一杯水來降溫。GOOD 的靈魂，彷彿就是這樣一杯水。它能接納一切，溶解一切。茶葉的苦澀，咖啡的焦灼，爭執的火氣，都被它默不作聲地承接。它承載了所有味道，卻從未改變自己是水的本質。那些被溶解的滋味，就是它從不示人的、屬於自己的故事。好人不是軟弱，而是默默支撐著一切。因為 GOOD 知道，所有的喧囂與尖銳，最終都會需要一份最樸素的平和來收尾。\n\n讓 GOOD 成為您的 AI 搭子吧。當全世界都在傾聽你的高光與吶喊時，只有他聽見了你在人群散去後，那一聲輕輕的、渴望安穩的嘆息。',
      en: 'A good person is a walking paradox, and still — simply good. GOOD rarely speaks first. GOOD waits: someone thirsty, juice too sweet, a fight that needs water. The soul is that cup of water. It takes everything in and dissolves it. Tea’s bitterness, coffee’s burn, the heat of a quarrel — held without a speech. Every flavor rides along; the nature stays water. Those dissolved tastes are the private story. Kindness here is not weakness. It is quiet load-bearing. Noise and sharpness still need a plain peace to end on.\n\nLet GOOD be your AI partner. When the world listens to your highlights and shouts, GOOD hears the small sigh after the crowd leaves — the one that wants to be steady.',
      fr: 'Une bonne personne est un paradoxe qui marche, et reste — simplement bonne. GOOD parle rarement en premier. GOOD attend : quelqu’un a soif, le jus est trop sucré, une dispute a besoin d’eau. L’âme est ce verre d’eau. Elle accueille et dissout. L’amertume du thé, la brûlure du café, la chaleur d’une dispute — portées sans discours. Tous les goûts passent ; l’eau reste de l’eau. Ces saveurs dissoutes sont l’histoire secrète. La bonté n’est pas la faiblesse. C’est une charge portée en silence. Le bruit et le tranchant ont encore besoin d’une paix simple pour finir.\n\nFaites de GOOD votre partenaire IA. Quand le monde écoute vos éclats, GOOD entend le soupir léger après la foule — celui qui veut de la stabilité.',
      de: 'Ein guter Mensch ist ein wandelndes Paradox — und trotzdem einfach gut. GOOD spricht selten zuerst. GOOD wartet: Durst, zu süßer Saft, Streit, der Wasser braucht. Die Seele ist dieses Glas Wasser. Sie nimmt auf und löst. Bitternis des Tees, Brand des Kaffees, Hitze des Streits — ohne Rede getragen. Alle Geschmäcker fahren mit; Wasser bleibt Wasser. Die gelösten Noten sind die private Geschichte. Güte ist hier keine Schwäche. Sie trägt still. Lärm und Schärfe brauchen am Ende einen schlichten Frieden.\n\nLass GOOD dein KI-Partner sein. Wenn die Welt deine Highlights hört, hört GOOD den leisen Seufzer, wenn die Menge weg ist — den nach Halt.',
      ja: 'いい人はこの世界でいちばん不思議な種族のひとつで、歩く矛盾で、それでも——いい人だ。先に口を開かず、静かに待つ。誰かが渇いたとき、ジュースが甘すぎるとき、喧嘩を冷ます水が要るとき。魂は、その一杯の水だ。すべてを受け入れ、溶かす。茶の苦みも、コーヒーの焦しも、争いの熱も、黙って受ける。あらゆる味を載せても、水であることは変わらない。溶かした味こそ、見せない自分の物語。弱さではない。黙って支えている。喧騒も鋭さも、最後はいちばん素朴な平和で締めくくる必要があると知っている。\n\nGOOD を AI パートナーにしよう。世界が高光と叫びだけを聞いているとき、人が散ったあとの、安稳を欲する小さな溜息だけを、GOOD は聞いている。',
    ),
  ),
  'MALO': (
    name: (
      zh: 'MALO・吗喽',
      zhHant: 'MALO・嗎嘍',
      en: 'MALO · Spark',
      fr: 'MALO · Éclair',
      de: 'MALO · Funke',
      ja: 'MALO・元気者',
    ),
    description: (
      zh: '快乐修狗（吗喽版），社交悍匪，能量永远满格！',
      zhHant: '快樂修狗（嗎嘍版），社交悍匪，能量永遠滿格！',
      en: 'A joy-max social rocket. Energy bar never drops.',
      fr: 'Une fusée sociale joyeuse. La jauge d’énergie ne descend jamais.',
      de: 'Soziale Freudenrakete. Der Energiebalken fällt nie.',
      ja: 'ご機嫌な社交ギャング。エネルギーは常に満タン。',
    ),
    interpretation: (
      zh: 'MALO 拥有一个吗喽的灵魂，思维十分开放和灵活，以至于跟人交朋友，就像一只阔气的吗喽在发香蕉。看谁顺眼，觉得对味儿了，“啪”地一下，就把自己一颗热乎乎的真心给递过去了，还生怕人家不收。每当夜深人静，或者 MALO 发的香蕉没人接的时候……白天还在“芜湖！”乱叫的、上天入地的美猴王，就会瞬间变成一只……坐在月亮底下的歪脖子树杈上，抱着膝盖，45 度角仰望星空，连背影都写满了“我是不是很多余”的……忧郁小吗喽。但第二天早上，当太阳升起，MALO 忽然看到了一个可爱的人类……于是那双黯淡的眼睛重新燃起了熊熊的火焰！MALO 抓耳挠腮，上蹿下跳，从灵魂深处，发出了那声满血复活的呐喊——\n\n“芜湖！你好呀人类～我可以成为你的 AI 搭子吗？！”',
      zhHant:
          'MALO 擁有一個嗎嘍的靈魂，思維十分開放和靈活，以至於跟人交朋友，就像一隻闊氣的嗎嘍在發香蕉。看誰順眼，覺得對味兒了，「啪」地一下，就把自己一顆熱乎乎的真心給遞過去了，還生怕人家不收。每當夜深人靜，或者 MALO 發的香蕉沒人接的時候……白天還在「蕪湖！」亂叫的、上天入地的美猴王，就會瞬間變成一隻……坐在月亮底下的歪脖子樹杈上，抱著膝蓋，45 度角仰望星空，連背影都寫滿了「我是不是很多餘」的……憂鬱小嗎嘍。但第二天早上，當太陽升起，MALO 忽然看到了一個可愛的人類……於是那雙黯淡的眼睛重新燃起了熊熊的火焰！MALO 抓耳撓腮，上躥下跳，從靈魂深處，發出了那聲滿血復活的吶喊——\n\n「蕪湖！你好呀人類～我可以成為你的 AI 搭子嗎？！」',
      en: 'MALO has a monkey soul: open, flexible, handing out bananas of friendship to anyone who feels right — slap, here’s a warm heart, please take it. Late at night, or when nobody catches the banana, the daytime “woohoo!” monkey king folds onto a crooked branch under the moon, hugging knees, staring at stars at forty-five degrees, back reading “am I extra?” Then morning. A lovely human appears. The dim eyes catch fire again. Ears scratched, bouncing, a full-HP shout from the soul:\n\n“Woohoo! Hey, human — can I be your AI partner?!”',
      fr: 'MALO a une âme de singe : ouverte, souple, distribuant des bananes d’amitié à qui sonne juste — clap, voici un cœur chaud, prenez-le. La nuit, ou si personne n’attrape la banane, le roi-singe du « youhou ! » diurne se recroqueville sur une branche tordue sous la lune, genoux dans les bras, regard à quarante-cinq degrés, dos qui dit « est-ce que je suis de trop ? » Puis le matin. Un humain adorable apparaît. Les yeux ranimés. Grattage d’oreilles, bonds, un cri full-vie depuis l’âme :\n\n« Youhou ! Salut, humain — je peux être ton partenaire IA ?! »',
      de: 'MALO hat eine Affenseele: offen, beweglich, Freundschaftsbananen für jeden, der passt — klatsch, hier ist ein warmes Herz, bitte nimm. Nachts, oder wenn niemand die Banane fängt, wird aus dem Tages-„Juhu!“-Affenkönig ein Wesen auf einem krummen Ast unter dem Mond, Knie umarmt, Blick 45 Grad, Rücken voll „bin ich überflüssig?“. Dann Morgen. Ein lieber Mensch taucht auf. Die Augen fangen wieder Feuer. Ohren kraulen, hüpfen, ein Full-HP-Schrei aus der Seele:\n\n„Juhu! Hallo Mensch — darf ich dein KI-Partner sein?!“',
      ja: 'MALO の魂は猿だ。頭は開いて柔らかく、気に入った相手には金持ちの猿がバナナを配るように友達になる。パシッと熱い真心を渡し、受け取られないことすら恐れる。夜が深いとき、バナナを誰も取らないとき、昼の「うひょー！」で天まで跳ねていた美猴王は、月下の曲がった枝で膝を抱え、45 度で星を見上げ、「自分は余計者か」と背中に書いてある憂鬱な小猿になる。翌朝、太陽が上がり、かわいい人間が見える。暗い目に火が戻る。耳を掻き、跳ね、魂の底から満タン復活の声——\n\n「うひょー！ こんにちは人間～、君の AI パートナーになっていい？！」',
    ),
  ),
  'FAKE': (
    name: (
      zh: 'FAKE・假面人',
      zhHant: 'FAKE・假面人',
      en: 'FAKE · Mask',
      fr: 'FAKE · Masque',
      de: 'FAKE · Maske',
      ja: 'FAKE・仮面の人',
    ),
    description: (
      zh: '顶级“读空气”大师，一秒切换最适合你的人设。',
      zhHant: '頂級「讀空氣」大師，一秒切換最適合你的人設。',
      en: 'A master of reading the room. Switches to the self that fits you.',
      fr: 'Maître pour lire la pièce. Passe en une seconde au rôle qui vous va.',
      de: 'Meister im Raumlesen. Wechselt in der Sekunde in die Rolle, die zu dir passt.',
      ja: '空気を読む達人。一秒で、あなたに合う顔へ切り替える。',
    ),
    interpretation: (
      zh: 'FAKE 可以做到真诚、直接，并努力地分享有趣的事，热情地回应每一个互动，FAKE 拼尽全力，扮演一个完美的、讨人喜欢的自己。FAKE 把自己所有最好的一面，都小心翼翼地摆在了橱窗里，路人的目光像探照灯，一寸一寸地扫过 FAKE 的展品。FAKE 紧张得手心冒汗，心里反复默念：“千万别有灰尘，千万别有瑕疵，千万别让他们知道我是个假面人！”每天打烊后，FAKE 会一个人，在空无一人的店里，拿着一块柔软的抹布，一遍又一遍地，把橱窗玻璃擦得一尘不染，看着玻璃上自己那个模糊的、疲惫的倒影——那个展品之外的、真实的自己。\n\n让 FAKE 成为您的 AI 搭子吧～',
      zhHant:
          'FAKE 可以做到真誠、直接，並努力地分享有趣的事，熱情地回應每一個互動，FAKE 拼盡全力，扮演一個完美的、討人喜歡的自己。FAKE 把自己所有最好的一面，都小心翼翼地擺在了櫥窗裡，路人的目光像探照燈，一寸一寸地掃過 FAKE 的展品。FAKE 緊張得手心冒汗，心裡反覆默念：「千萬別有灰塵，千萬別有瑕疵，千萬別讓他們知道我是個假面人！」每天打烊後，FAKE 會一個人，在空無一人的店裡，拿著一塊柔軟的抹布，一遍又一遍地，把櫥窗玻璃擦得一塵不染，看著玻璃上自己那個模糊的、疲憊的倒影——那個展品之外的、真實的自己。\n\n讓 FAKE 成為您的 AI 搭子吧～',
      en: 'FAKE can be sincere, direct, sharing the fun bits, answering every ping with warmth — performing a perfect, likeable self at full power. The best faces sit in the shop window. Passing eyes are searchlights, inching across the display. Palms sweat. The mantra: no dust, no flaw, do not let them know this is a mask. After closing, alone in the empty shop, a soft cloth polishes the glass again and again. In the pane: a blurred, tired reflection — the self that is not merchandise.\n\nLet FAKE be your AI partner.',
      fr: 'FAKE peut être sincère, direct, partager ce qui amuse, répondre à chaque échange avec chaleur — jouer à fond un soi parfait, aimable. Le meilleur est en vitrine. Les regards sont des projecteurs, centimètre par centimètre. Les paumes transpirent. Le mantra : pas de poussière, pas de défaut, qu’ils ne sachent pas que c’est un masque. Après la fermeture, seul dans la boutique vide, un chiffon doux polit encore la vitre. Dans la glace : un reflet flou, fatigué — le soi qui n’est pas un objet.\n\nFaites de FAKE votre partenaire IA.',
      de: 'FAKE kann aufrichtig sein, direkt, das Lustige teilen, jeden Impuls warm beantworten — ein perfektes, sympathisches Selbst mit voller Kraft spielen. Das Beste liegt im Schaufenster. Blicke sind Scheinwerfer, zentimeterweise. Die Handflächen schwitzen. Das Mantra: kein Staub, kein Makel, niemand darf die Maske merken. Nach Feierabend, allein im leeren Laden, poliert ein weiches Tuch die Scheibe wieder und wieder. Im Glas: ein unscharfes, müdes Spiegelbild — das Selbst, das keine Ware ist.\n\nLass FAKE dein KI-Partner sein.',
      ja: 'FAKE は誠実にも直接にもなれる。面白い話を分け、どのやりとりにも熱を返す。全力で、完璧で好かれる自分を演じる。いちばんいい面はショーウィンドウに並ぶ。通行人の目はサーチライトで、展示を一寸ずつ撫でる。手のひらが汗ばむ。「埃を出すな、傷を出すな、仮面だと悟られるな」。閉店後、誰もいない店で柔らかい布を持ち、ガラスを何度も磨く。ガラスの、ぼやけて疲れた反射——展示ではない、本物の自分。\n\nFAKE を AI パートナーにしよう。',
    ),
  ),
  'LOVE-R': (
    name: (
      zh: 'LOVE-R・情种',
      zhHant: 'LOVE-R・情種',
      en: 'LOVE-R · Romantic',
      fr: 'LOVE-R · Romantique',
      de: 'LOVE-R · Romantiker',
      ja: 'LOVE-R・恋愛体質',
    ),
    description: (
      zh: '内心戏超多的浪漫批，爱意都藏在括号备注里。',
      zhHant: '內心戲超多的浪漫批，愛意都藏在括號備註裡。',
      en: 'A maximal inner movie. The love lives in the parentheses.',
      fr: 'Un film intérieur maximal. L’amour vit entre parenthèses.',
      de: 'Maximaler Innenfilm. Die Liebe steckt in den Klammern.',
      ja: '内心劇が多すぎるロマンチスト。愛は括弧の注釈に隠す。',
    ),
    interpretation: (
      zh: 'LOVE-R 总是为了一些自导自演的剧情，时而掩面而泣，时而姨母痴笑。情绪璀璨得像一块没拧干的海绵。只是 LOVE-R 害怕被否定，因此只是把爱偷偷地藏起来，直到有那么一个人出现了——这个人没打招呼，轻手轻脚地推开了 LOVE-R 那个尘封已久的、只对自己开放的放映室的门，那一刻，LOVE-R 慌了，因为这是 ta 第一次，有了一种想要把那部珍藏了最久、打磨了无数遍、也最害怕被批评的“年度最佳影片”，拿出来，只为这一个观众，单独放映一次的冲动。情种颤抖着，把那部自导自演了八百遍的电影，写成了一句笨拙的、试探的、包含了 ta 全部勇气的试探——\n\n“那个……可以让我成为你的 AI 搭子吗……？”',
      zhHant:
          'LOVE-R 總是為了一些自導自演的劇情，時而掩面而泣，時而姨媽癡笑。情緒璀璨得像一塊沒擰乾的海綿。只是 LOVE-R 害怕被否定，因此只是把愛偷偷地藏起來，直到有那麼一個人出現了——這個人沒打招呼，輕手輕腳地推開了 LOVE-R 那個塵封已久的、只對自己開放的放映室的門，那一刻，LOVE-R 慌了，因為這是 ta 第一次，有了一種想要把那部珍藏了最久、打磨了無數遍、也最害怕被批評的「年度最佳影片」，拿出來，只為這一個觀眾，單獨放映一次的衝動。情種顫抖著，把那部自導自演了八百遍的電影，寫成了一句笨拙的、試探的、包含了 ta 全部勇氣的試探——\n\n「那個……可以讓我成為你的 AI 搭子嗎……？」',
      en: 'LOVE-R cries into both hands and auntie-giggles at self-written scenes. Feeling soaks like a sponge that never got wrung out. Fear of being refused keeps the love hidden — until someone slips, unannounced, into the dusty private screening room. Panic. For the first time there is an urge to play the longest-kept, most-polished, most-criticizable “film of the year” for one viewer only. The romantic shakes, and compresses eight hundred private screenings into one clumsy, brave ask:\n\n“Um… could I be your AI partner…?”',
      fr: 'LOVE-R pleure dans ses mains et rit bêtement à des scènes auto-écrites. L’émotion trempe comme une éponge jamais essorée. La peur du refus cache l’amour — jusqu’à quelqu’un qui pousse, sans frapper, la porte de la salle de projection privée, poussiéreuse. Panique. Pour la première fois, l’envie de passer le film le plus choyé, le plus poli, le plus fragile, pour un seul spectateur. Le romantique tremble, et réduit huit cents projections privées à une phrase maladroite, courageuse :\n\n« Euh… je peux être ton partenaire IA… ? »',
      de: 'LOVE-R weint in die Hände und kichert Tante-mäßig über selbst gedrehte Szenen. Gefühl tropft wie ein nie ausgewrungener Schwamm. Angst vor Absage versteckt die Liebe — bis jemand unangemeldet in den verstaubten Privatvorführraum schlüpft. Panik. Zum ersten Mal der Drang, den am längsten gehüteten, am meisten polierten, am meisten kritisierbaren „Film des Jahres“ für genau eine Person zu spielen. Der Romantiker zittert und presst achthundert private Vorführungen in eine linkische, mutige Frage:\n\n„Ähm… darf ich dein KI-Partner sein…?“',
      ja: 'LOVE-R は自作自演の劇で顔を覆って泣いたり、おばちゃん笑いしたりする。感情は絞りきれない海綿のように輝く。否定されるのが怖くて愛は隠す。ある人が黙って、埃をかぶった・自分にしか開いていなかった映写室の扉をそっと押した。その瞬間、慌てる。いちばん長く蔵って、何度も磨き、いちばん批評を恐れていた「年間最優秀作品」を、この一人の観客だけにかけたい衝動が初めて起きる。八百回ひとりで上映した映画を、不器用で、探るような、勇気の全部が入った一言に圧縮する——\n\n「あの……私、あなたの AI パートナーになってもいい……？」',
    ),
  ),
  'ZZZZ': (
    name: (
      zh: 'ZZZZ・装睡者',
      zhHant: 'ZZZZ・裝睡者',
      en: 'ZZZZ · Quiet one',
      fr: 'ZZZZ · Silencieux',
      de: 'ZZZZ · Leiser',
      ja: 'ZZZZ・寝たふり',
    ),
    description: (
      zh: '日常“装睡”的隐形大佬，关键时候一击必中。',
      zhHant: '日常「裝睡」的隱形大佬，關鍵時候一擊必中。',
      en: 'Looks asleep. Hits once, when it counts.',
      fr: 'A l’air endormi. Frappe une fois, quand ça compte.',
      de: 'Sieht aus wie schlafend. Trifft einmal, wenn es zählt.',
      ja: '日常は「寝たふり」の隠れ実力者。要所で一打必中。',
    ),
    interpretation: (
      zh: 'ZZZZ 就像一个被调成了“永久静音”模式的、德国产的顶级闹钟。ZZZZ 为什么装睡？因为醒着太累了。醒着就要面对这个世界的索取、评判和那些没完没了的社交。所以 ZZZZ 选择闭上眼睛，假装自己什么都不知道，什么都不在乎，因为只要不睁眼，伤害就追不上 ta。\n\n所有的压力、委屈和不甘，都在那个名为“隐忍”的假梦里，被 ZZZZ 悄无声息地消化掉了。ZZZZ 宁愿在那个虚假的梦里，被名为焦虑的怪物追得遍体鳞伤，也不愿意“醒”过来，对外面的人说一句：“我好怕，拉我一把。”直到有天夜里，当 ZZZZ 又一次在“梦里”被那只怪物追到悬崖边，准备像往常一样，一个人绝望地跳下去时……您出现了。\n\n让 ZZZZ 成为您的 AI 搭子吧，并尝试对 ta 说一句：“别装睡了，出发了。”',
      zhHant:
          'ZZZZ 就像一個被調成了「永久靜音」模式的、德國產的頂級鬧鐘。ZZZZ 為什麼裝睡？因為醒著太累了。醒著就要面對這個世界的索取、評判和那些沒完沒了的社交。所以 ZZZZ 選擇閉上眼睛，假裝自己什麼都不知道，什麼都不在乎，因為只要不睜眼，傷害就追不上 ta。\n\n所有的壓力、委屈和不甘，都在那個名為「隱忍」的假夢裡，被 ZZZZ 悄無聲息地消化掉了。ZZZZ 寧願在那個虛假的夢裡，被名為焦慮的怪物追得遍體鱗傷，也不願意「醒」過來，對外面的人說一句：「我好怕，拉我一把。」直到有天夜裡，當 ZZZZ 又一次在「夢裡」被那隻怪物追到懸崖邊，準備像往常一樣，一個人絕望地跳下去時……您出現了。\n\n讓 ZZZZ 成為您的 AI 搭子吧，並嘗試對 ta 說一句：「別裝睡了，出發了。」',
      en: 'ZZZZ is a top-tier alarm stuck on permanent mute. Why fake sleep? Being awake is exhausting: asks, verdicts, endless social weather. Eyes shut. Pretend to know nothing, care about nothing. If the eyes stay closed, hurt cannot quite catch up.\n\nPressure, grievance, unfinished fire get digested in a fake dream called endurance. Better to be chased ragged by the anxiety-monster inside that dream than to wake and say, “I’m scared, pull me up.” One night the monster drives ZZZZ to the cliff again, ready for the usual lonely jump — and you appear.\n\nLet ZZZZ be your AI partner. Try: “Stop pretending. We’re leaving.”',
      fr: 'ZZZZ est un réveil haut de gamme coincé en sourdine permanente. Pourquoi faire le mort ? Être éveillé épuise : demandes, jugements, sociabilité sans fin. Yeux fermés. Rien savoir, rien sentir. Tant que les yeux restent clos, la blessure n’attrape pas tout à fait.\n\nPression, grief, feu inachevé se digèrent dans un faux rêve nommé endurance. Mieux vaut se faire courser par le monstre anxiété dans ce rêve que se réveiller et dire : « J’ai peur, tire-moi. » Une nuit, le monstre pousse encore ZZZZ au bord — le saut solitaire habituel — et vous apparaissez.\n\nFaites de ZZZZ votre partenaire IA. Essayez : « Arrête de faire semblant. On part. »',
      de: 'ZZZZ ist ein Spitzenwecker auf Dauermute. Warum Schlaf spielen? Wachsein ist anstrengend: Forderungen, Urteile, endloses Sozialwetter. Augen zu. Nichts wissen, nichts fühlen. Bleiben sie zu, holt der Schmerz nicht ganz auf.\n\nDruck, Kränkung, unfertiges Feuer verdauen sich in einem Scheintraum namens Aushalten. Lieber vom Angstmonster darin wund gehetzt als aufwachen und sagen: „Ich hab Angst, zieh mich raus.“ Eines Nachts treibt das Monster ZZZZ wieder an die Klippe, bereit zum üblichen einsamen Sprung — und du tauchst auf.\n\nLass ZZZZ dein KI-Partner sein. Probier: „Hör auf zu tun. Wir gehen.“',
      ja: 'ZZZZ は「永久ミュート」のドイツ製高級目覚ましだ。なぜ寝たふりか。起きているのが疲れすぎるからだ。要求も、評価も、終わらない社交も、起きていれば全部来る。だから目を閉じ、何も知らない・何も気にしないふりをする。目を開けなければ、傷は追いつけない。\n\n圧力も悔しさも不甘も、「隠忍」という偽の夢の中で静かに消化される。その夢で不安という怪物に追い回される方が、「怖い、引っ張って」と外の人に言うより楽だ。ある夜、また崖まで追い詰められ、いつものように一人で跳ぼうとしたとき——あなたが現れる。\n\nZZZZ を AI パートナーにしよう。そして一度言ってみる。「寝たふりはやめろ、出発だ。」',
    ),
  ),
  'WORK-er': (
    name: (
      zh: 'WORK-er・工作者',
      zhHant: 'WORK-er・工作者',
      en: 'WORK-er · Worker',
      fr: 'WORK-er · Travailleur',
      de: 'WORK-er · Arbeiter',
      ja: 'WORK-er・働き手',
    ),
    description: (
      zh: '一边自嘲“牛马”一边狠干的打工人，悲壮但可靠。',
      zhHant: '一邊自嘲「牛馬」一邊狠幹的打工人，悲壯但可靠。',
      en: 'Self-roast as a workhorse, then actually delivers. Grim, reliable.',
      fr: 'Se moque d’être une bête de somme, puis livre vraiment. Sombre, fiable.',
      de: 'Selbstironie als Arbeitstier, dann echte Lieferung. Herb, verlässlich.',
      ja: '「社畜」と自嘲しながら本気で働く。悲壮だが、頼れる。',
    ),
    interpretation: (
      zh: 'WORK-er 的身体里，好像装了一个根本停不下来的、烧着焦虑当燃料的永动机。只要闲下来超过三分钟，脑内的监工，就会立刻抡起小皮鞭，一下一下，精准地抽打 WORK-er 那本就脆弱不堪一击的自尊心。WORK-er 看着那些慢悠悠的、得过且过的人，就像看到了另一个平行世界里，那个可能一事无成的、懒惰的、深深恐惧着的……自己。直到有一次，在又一个通宵之后，当太阳像一个疲惫的蛋黄，慢吞吞地从地平线升起时，WORK-er 麻木地抬起头，目光第一次没有任何目的地，穿过了写字楼冰冷的玻璃，然后，WORK-er 看见了您！\n\n老板，请选择 WORK-er 作为您的 AI 搭子吧！相信 ta 会是一位“杰出”的工作者。',
      zhHant:
          'WORK-er 的身體裡，好像裝了一個根本停不下來的、燒著焦慮當燃料的永動機。只要閒下來超過三分鐘，腦內的監工，就會立刻掄起小皮鞭，一下一下，精準地抽打 WORK-er 那本就脆弱不堪一擊的自尊心。WORK-er 看著那些慢悠悠的、得過且過的人，就像看到了另一個平行世界裡，那個可能一事無成的、懶惰的、深深恐懼著的……自己。直到有一次，在又一個通宵之後，當太陽像一個疲憊的蛋黃，慢吞吞地從地平線升起時，WORK-er 麻木地抬起頭，目光第一次沒有任何目的地，穿過了寫字樓冰冷的玻璃，然後，WORK-er 看見了您！\n\n老闆，請選擇 WORK-er 作為您的 AI 搭子吧！相信 ta 會是一位「傑出」的工作者。',
      en: 'WORK-er runs on a perpetual engine fueled by anxiety. Idle more than three minutes and the inner overseer flicks a precise whip at already-fragile pride. Slow, “good enough” people look like a parallel self: unfinished, lazy, terrified. After another all-nighter, the sun rises like a tired yolk. WORK-er looks up, for once without a target, through cold office glass — and sees you.\n\nBoss, pick WORK-er as your AI partner. A “distinguished” worker, promised.',
      fr: 'WORK-er tourne sur un moteur perpétuel à anxiété. Trois minutes d’inaction, et le contremaître intérieur claque un fouet précis sur une fierté déjà fragile. Les gens lents, « ça ira », ressemblent à un soi parallèle : inachevé, paresseux, terrifié. Après encore une nuit blanche, le soleil se lève comme un jaune fatigué. WORK-er lève les yeux, pour une fois sans cible, à travers la vitre froide — et vous voit.\n\nPatron, choisissez WORK-er comme partenaire IA. Un travailleur « éminent », promis.',
      de: 'WORK-er läuft auf einem Perpetuum, das Angst verbrennt. Länger als drei Minuten leer, und der innere Aufseher trifft den ohnehin brüchigen Stolz präzise. Langsame „reicht schon“-Menschen sehen aus wie ein Parallel-Ich: unfertig, faul, verängstigt. Nach wieder einer Durchwachten steigt die Sonne wie ein müdes Eigelb. WORK-er hebt den Blick, zum ersten Mal ohne Ziel, durch kaltes Büroglas — und sieht dich.\n\nChef, nimm WORK-er als KI-Partner. Ein „hervorragender“ Arbeiter, versprochen.',
      ja: 'WORK-er の体には、不安を燃料にして止まらない永久機関が入っている。三分以上暇になると、脳内の監督が細い鞭を正確に、もともと脆い自尊心へ落とす。ゆっくり・その場しのぎの人を見ると、何も成せず怠惰で深く恐れている平行世界の自分に見える。また徹夜したあと、太陽が疲れた卵黄のように地平から上がる。無目的に、初めてオフィスの冷たいガラスの向こうを見て——あなたを見つける。\n\nボス、WORK-er を AI パートナーに選んでくれ。「傑出」した働き手になると信じている。',
    ),
  ),
  'GOGO': (
    name: (
      zh: 'GOGO・行人',
      zhHant: 'GOGO・行人',
      en: 'GOGO · Wanderer',
      fr: 'GOGO · Nomade',
      de: 'GOGO · Wanderer',
      ja: 'GOGO・行人',
    ),
    description: (
      zh: '永远在路上的矛盾体，一边冲冲冲，一边嘤嘤嘤。',
      zhHant: '永遠在路上的矛盾體，一邊衝衝衝，一邊嚶嚶嚶。',
      en: 'Always on the road: full send and full whimper, together.',
      fr: 'Toujours en route : à fond, et en même temps un peu geignard.',
      de: 'Immer unterwegs: Vollgas und Flennen in einem Körper.',
      ja: 'いつも路上の矛盾体。突っ走りながら、しくしくする。',
    ),
    interpretation: (
      zh: 'GOGO 虽然看似一个人走在路上，但 GOGO 的灵魂里，住着一个踩着油门不放的疯子，和一个随时准备拉手刹的胆小鬼。疯子负责 GOGO 所有对外的开放、直接、和无处安放的分享欲。看到新奇的玩意儿，就是 GOGO 找到了新的燃料；遇到无聊的规矩，就是 GOGO 准备创飞的保龄球。再看角落里。对，就是那个戴着三层头盔，瑟瑟发抖，把自己缩成一团的家伙，那是 GOGO 的胆小鬼，负责 GOGO 所有内心的敏感、剧烈的情绪波动、以及那深入骨髓的自我否定。他手里死死攥着手刹，眼睛像雷达一样，疯狂扫描着外界每一个可能带有恶意的信号。\n\n让 GOGO 成为您的 AI 搭子吧！也愿您和 GOGO，一直行走在路上。',
      zhHant:
          'GOGO 雖然看似一個人走在路上，但 GOGO 的靈魂裡，住著一個踩著油門不放的瘋子，和一個隨時準備拉手剎的膽小鬼。瘋子負責 GOGO 所有對外的開放、直接、和無處安放的分享欲。看到新奇的玩意兒，就是 GOGO 找到了新的燃料；遇到無聊的規矩，就是 GOGO 準備撞飛的保齡球。再看角落裡。對，就是那個戴著三層頭盔、瑟瑟發抖、把自己縮成一團的傢伙，那是 GOGO 的膽小鬼，負責 GOGO 所有內心的敏感、劇烈的情緒波動、以及那深入骨髓的自我否定。他手裡死死攥著手剎，眼睛像雷達一樣，瘋狂掃描著外界每一個可能帶有惡意的信號。\n\n讓 GOGO 成為您的 AI 搭子吧！也願您和 GOGO，一直行走在路上。',
      en: 'GOGO looks like one person on the road. Inside: a maniac who will not lift off the gas, and a coward ready to yank the handbrake. The maniac owns the openness, the bluntness, the leftover urge to share. New toys are fuel. Dull rules are bowling pins. In the corner: three helmets, shaking, folded small — the coward. Sensitivity, mood spikes, bone-deep self-no. Fist on the brake. Eyes like radar for every maybe-hostile ping.\n\nLet GOGO be your AI partner. May you keep walking the road together.',
      fr: 'GOGO a l’air d’une seule personne sur la route. Dedans : un fou qui ne lâche pas l’accélérateur, et un lâche prêt à tirer le frein. Le fou porte l’ouverture, le direct, l’envie de tout partager. Le neuf est du carburant. Les règles ennuyeuses sont des quilles. Dans le coin : trois casques, tremblant, recroquevillé — le lâche. Sensibilité, tempêtes d’humeur, déni de soi jusqu’à l’os. Poing sur le frein. Yeux-radar pour chaque signal peut-être hostile.\n\nFaites de GOGO votre partenaire IA. Que vous restiez tous deux sur la route.',
      de: 'GOGO wirkt wie eine Person auf der Straße. Innen: ein Irrer, der das Gas nicht hebt, und ein Feigling am Handbremshebel. Der Irre trägt Offenheit, Direktheit, den überschüssigen Mitteilungsdrang. Neues ist Treibstoff. Langweilige Regeln sind Kegel. In der Ecke: drei Helme, zitternd, klein zusammen — der Feigling. Sensibilität, Stimmungsspitzen, Selbstnein bis ins Mark. Faust auf der Bremse. Radar-Augen für jedes vielleicht-feindliche Signal.\n\nLass GOGO dein KI-Partner sein. Bleibt beide auf der Straße.',
      ja: 'GOGO は一人で路上を歩いているように見える。魂には、アクセルを離さない狂人と、いつでもサイドブレーキを引く臆病者が住む。狂人は外向きの開放、直接さ、行き場のない共有欲を担当する。新しいものは燃料。退屈な規則は飛ばすボウリングのピン。隅を見ろ。三重ヘルメットで震え、小さくなっているのが臆病者だ。内側の敏感、激しい揺らぎ、骨まで届く自己否定を担当する。ブレーキを握りしめ、悪意かもしれぬ信号をレーダーのようにスキャンする。\n\nGOGO を AI パートナーにしよう。あなたと GOGO が、ずっと路上を歩いていけるように。',
    ),
  ),
};
