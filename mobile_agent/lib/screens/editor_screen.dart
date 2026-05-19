import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../core/theme.dart';
import '../core/constants.dart';
import '../widgets/ai_chat_panel.dart';

// ── Open Tab Model ──────────────────────────────────────────────────────────

class _OpenTab {
  final String id;
  String fileName, filePath, language;
  final TextEditingController controller;
  final FocusNode focusNode;
  bool isModified, readOnly;
  String? originalContent;
  int cursorLine, cursorColumn;
  final DateTime openedAt;

  _OpenTab({
    required this.id, required this.fileName, required this.filePath,
    required this.language, required this.controller, required this.focusNode,
    this.isModified = false, this.originalContent, this.readOnly = false,
    this.cursorLine = 1, this.cursorColumn = 1,
  }) : openedAt = DateTime.now();

  int get lineCount => controller.text.isEmpty ? 1 : '\n'.allMatches(controller.text).length + 1;
  int get wordCount {
    final t = controller.text.trim();
    return t.isEmpty ? 0 : t.split(RegExp(r'\s+')).where((s) => s.isNotEmpty).length;
  }
  int get charCount => controller.text.length;
  void dispose() { controller.dispose(); focusNode.dispose(); }
}

// ── Syntax Highlighter ──────────────────────────────────────────────────────

class SyntaxHighlighter {
  SyntaxHighlighter._();

  static final Map<String, Set<String>> _keywords = {
    'dart': {'abstract','as','assert','async','await','break','case','catch','class','const','continue','default','do','else','enum','export','extends','extension','external','factory','false','final','finally','for','Function','get','if','implements','import','in','is','late','library','mixin','new','null','operator','part','required','rethrow','return','set','show','static','super','switch','sync','this','throw','true','try','typedef','var','void','while','with','yield','dynamic','covariant','deferred'},
    'python': {'and','as','assert','async','await','break','class','continue','def','del','elif','else','except','False','finally','for','from','global','if','import','in','is','lambda','None','nonlocal','not','or','pass','raise','return','True','try','while','with','yield'},
    'javascript': {'async','await','break','case','catch','class','const','continue','debugger','default','delete','do','else','export','extends','false','finally','for','function','if','import','in','instanceof','let','new','null','return','static','super','switch','this','throw','true','try','typeof','var','void','while','with','yield'},
    'typescript': {'async','await','break','case','catch','class','const','continue','debugger','default','delete','do','else','export','extends','false','finally','for','function','if','import','in','instanceof','interface','let','new','null','of','private','protected','public','readonly','return','static','super','switch','this','throw','true','try','type','typeof','var','void','while','with','yield','as','declare','abstract','implements','enum','keyof','never','unknown','from','is'},
    'go': {'break','case','chan','const','continue','default','defer','else','fallthrough','for','func','go','goto','if','import','interface','map','package','range','return','select','struct','switch','type','var'},
    'rust': {'as','async','await','break','const','continue','crate','dyn','else','enum','extern','false','fn','for','if','impl','in','let','loop','match','mod','move','mut','pub','ref','return','self','Self','static','struct','super','trait','true','type','unsafe','use','where','while'},
    'java': {'abstract','assert','boolean','break','byte','case','catch','char','class','const','continue','default','do','double','else','enum','extends','final','finally','float','for','goto','if','implements','import','instanceof','int','interface','long','native','new','package','private','protected','public','return','short','static','strictfp','super','switch','synchronized','this','throw','throws','transient','try','void','volatile','while','true','false','null'},
    'kotlin': {'as','as?','break','by','catch','class','companion','const','constructor','continue','crossinline','data','do','dynamic','else','enum','external','false','field','file','final','finally','for','fun','get','if','import','in','infix','init','inline','inner','interface','internal','is','it','lateinit','noinline','null','object','open','operator','out','override','package','private','property','protected','public','receiver','reified','return','sealed','set','super','suspend','tailrec','this','throw','true','try','typealias','val','var','vararg','when','where','while'},
    'swift': {'associatedtype','async','await','break','case','catch','class','continue','default','defer','deinit','do','else','enum','extension','fallthrough','false','fileprivate','for','func','guard','if','import','in','init','inout','internal','is','let','nonisolated','open','operator','private','protocol','public','repeat','rethrows','return','self','Self','some','static','struct','subscript','super','switch','throw','throws','true','try','typealias','var','where','while'},
    'cpp': {'alignas','alignof','and','and_eq','asm','auto','bitand','bitor','bool','break','case','catch','char','class','compl','concept','const','consteval','constexpr','constinit','const_cast','continue','co_await','co_return','co_yield','decltype','default','delete','do','double','dynamic_cast','else','enum','explicit','export','extern','false','float','for','friend','goto','if','inline','int','long','mutable','namespace','new','noexcept','not','not_eq','nullptr','operator','or','or_eq','private','protected','public','reflexpr','register','reinterpret_cast','requires','return','short','signed','sizeof','static','static_assert','static_cast','struct','switch','template','this','thread_local','throw','true','try','typedef','typeid','typename','union','unsigned','using','virtual','void','volatile','wchar_t','while','xor','xor_eq'},
    'c': {'auto','break','case','char','const','continue','default','do','double','else','enum','extern','float','for','goto','if','inline','int','long','register','restrict','return','short','signed','sizeof','static','struct','switch','typedef','union','unsigned','void','volatile','while','_Alignas','_Alignof','_Atomic','_Bool','_Complex','_Generic','_Imaginary','_Noreturn','_Static_assert','_Thread_local'},
    'html': {'!DOCTYPE','a','abbr','address','area','article','aside','audio','b','base','blockquote','body','br','button','canvas','caption','cite','code','col','colgroup','data','datalist','dd','del','details','dfn','dialog','div','dl','dt','em','embed','fieldset','figcaption','figure','footer','form','h1','h2','h3','h4','h5','h6','head','header','hr','html','i','iframe','img','input','ins','kbd','label','legend','li','link','main','map','mark','math','menu','meta','meter','nav','noscript','object','ol','optgroup','option','output','p','picture','pre','progress','q','rp','rt','ruby','s','samp','script','search','section','select','slot','small','source','span','strong','style','sub','summary','sup','svg','table','tbody','td','template','textarea','tfoot','th','thead','time','title','tr','track','u','ul','var','video','wbr'},
    'css': {'align-content','align-items','align-self','all','animation','appearance','aspect-ratio','backdrop-filter','background','border','bottom','box-shadow','box-sizing','caption-side','caret-color','clear','clip','color','columns','content','cursor','direction','display','filter','flex','float','font','gap','grid','height','hyphens','inset','isolation','justify-content','left','letter-spacing','line-height','list-style','margin','mask','max-height','max-width','min-height','min-width','mix-blend-mode','object-fit','opacity','order','outline','overflow','padding','pointer-events','position','quotes','resize','right','rotate','scale','scroll-behavior','tab-size','text-align','text-decoration','text-indent','text-overflow','text-shadow','text-transform','top','transform','transition','translate','user-select','vertical-align','visibility','white-space','width','word-break','word-spacing','writing-mode','z-index'},
    'sql': {'ADD','ALL','ALTER','AND','ANY','AS','ASC','BEGIN','BETWEEN','BY','CASCADE','CASE','CHECK','COLUMN','COMMIT','CONSTRAINT','CONVERT','CREATE','CROSS','CURRENT','CURRENT_DATE','CURRENT_TIME','CURRENT_TIMESTAMP','CURRENT_USER','CURSOR','DATABASE','DECLARE','DEFAULT','DELETE','DESC','DISTINCT','DROP','ELSE','END','ESCAPE','EXCEPT','EXEC','EXECUTE','EXISTS','FETCH','FOR','FOREIGN','FROM','FULL','FUNCTION','GRANT','GROUP','HAVING','IF','IN','INDEX','INNER','INSERT','INTERSECT','INTO','IS','JOIN','KEY','KILL','LEFT','LIKE','LINENO','MERGE','NOT','NULL','NULLIF','OF','OFF','ON','OPEN','OPTION','OR','ORDER','OUTER','OVER','PERCENT','PIVOT','PLAN','PRIMARY','PRINT','PROC','PROCEDURE','PUBLIC','RAISERROR','READ','REFERENCES','RETURN','REVERT','REVOKE','RIGHT','ROLLBACK','ROWCOUNT','RULE','SAVE','SCHEMA','SELECT','SET','SHUTDOWN','SOME','STATISTICS','SYSTEM_USER','TABLE','TEXTSIZE','THEN','TO','TOP','TRAN','TRANSACTION','TRIGGER','TRUNCATE','TRY','UNION','UNIQUE','UNPIVOT','UPDATE','USE','VALUES','VARYING','VIEW','WAITFOR','WHERE','WHILE','WITH'},
    'yaml': {'true','false','null','yes','no','on','off'},
    'shell': {'if','then','else','elif','fi','case','esac','for','while','do','done','in','function','return','exit','break','continue','shift','source','export','local','readonly','unset','alias','trap','wait','eval','exec','echo','printf','read','cd','pwd','ls','cat','grep','sed','awk','test','true','false'},
    'ruby': {'alias','and','begin','break','case','class','def','defined?','do','else','elsif','end','ensure','false','for','if','in','module','next','nil','not','or','redo','rescue','retry','return','self','super','then','true','undef','unless','until','when','while','yield'},
    'php': {'__halt_compiler','abstract','and','array','as','break','callable','case','catch','class','clone','const','continue','declare','default','die','do','echo','else','elseif','empty','enddeclare','endfor','endforeach','endif','endswitch','endwhile','eval','exit','extends','final','finally','fn','for','foreach','function','global','goto','if','implements','include','include_once','instanceof','insteadof','interface','isset','list','match','namespace','new','or','print','private','protected','public','readonly','require','require_once','return','static','switch','throw','trait','try','unset','use','var','while','xor','yield'},
    'xml': {'xml','version','encoding','standalone','DOCTYPE','ELEMENT','ATTLIST','ENTITY','NOTATION','CDATA','PCDATA','REQUIRED','IMPLIED','FIXED'},
  };

  static final Map<String, Set<String>> _types = {
    'dart': {'int','double','String','bool','List','Map','Set','Future','Stream','void','Object','dynamic','num','Iterable','Iterator','Symbol','Type','DateTime','Duration','RegExp','Exception','Error'},
    'typescript': {'number','string','boolean','any','void','never','unknown','object','symbol','bigint','undefined'},
    'swift': {'Int','Double','Float','Bool','String','Character','Array','Dictionary','Set','Optional','Any','AnyObject','Void','Never','Error','Result'},
    'java': {'byte','short','int','long','float','double','boolean','char','String','Object','Integer','Double','Boolean','Character','List','Map','Set','ArrayList','HashMap'},
    'kotlin': {'Byte','Short','Int','Long','Float','Double','Boolean','Char','String','Array','List','Map','Set','Unit','Nothing','Any','Pair','Triple'},
    'cpp': {'bool','char','double','float','int','long','short','signed','unsigned','void','wchar_t','size_t','auto','string','vector','map','set','array','tuple','optional','variant','unique_ptr','shared_ptr'},
    'c': {'char','double','float','int','long','short','signed','unsigned','void','size_t','FILE'},
  };

  static final Map<String, Set<String>> _builtins = {
    'python': {'print','len','range','enumerate','zip','map','filter','sorted','sum','min','max','abs','round','int','str','float','list','dict','set','tuple','open','input','type','isinstance','hasattr','getattr','super'},
    'javascript': {'console','Math','JSON','Object','Array','String','Number','Date','RegExp','Promise','Set','Map','parseInt','parseFloat','isNaN','setTimeout','setInterval'},
    'dart': {'print','debugPrint','identical','identicalHashCode','DateTime','Duration','Uri','RegExp'},
  };

  static String detectLanguage(String fileName) {
    final lower = fileName.toLowerCase();
    final dot = lower.lastIndexOf('.');
    if (dot == -1) return 'text';
    return SupportedLanguages.extensionMap[lower.substring(dot)] ?? 'text';
  }

  static String languageLabel(String language) {
    return SupportedLanguages.languages[language] ?? language[0].toUpperCase() + language.substring(1);
  }

  static List<TextSpan> highlightLine(String line, String language) {
    if (line.isEmpty) return [const TextSpan(text: '')];
    final kws = _keywords[language] ?? {};
    final tps = _types[language] ?? {};
    final blt = _builtins[language] ?? {};
    final allK = {...kws, ...tps};

    // Get comment patterns
    List<RegExp> commentRe;
    switch (language) {
      case 'python': commentRe = [RegExp(r'#.*$'), RegExp(r'""".*?"""'), RegExp(r"'''.*?'''")]; break;
      case 'html': commentRe = [RegExp(r'<!--.*?-->')]; break;
      case 'css': commentRe = [RegExp(r'/\*.*?\*/')]; break;
      case 'yaml': case 'shell': case 'ruby': case 'dockerfile': commentRe = [RegExp(r'#.*$')]; break;
      case 'sql': commentRe = [RegExp(r'--.*$'), RegExp(r'/\*.*?\*/')]; break;
      case 'markdown': commentRe = [RegExp(r'<!--.*?-->')]; break;
      default: commentRe = [RegExp(r'//.*$'), RegExp(r'/\*.*?\*/')]; break;
    }

    // String pattern
    RegExp? strRe;
    if (language != 'markdown' && language != 'yaml' && language != 'json') {
      strRe = RegExp(r'"([^"\\]|\\.)*"' r"|'([^'\\]|\\.)*'");
    }

    // Template literals
    RegExp? tplRe;
    if (language == 'dart' || language == 'javascript' || language == 'typescript') {
      tplRe = RegExp(r'\$(\w+|\{[^}]*\})');
    }

    final spans = <TextSpan>[];
    int pos = 0;

    while (pos < line.length) {
      bool matched = false;

      // Try comment patterns (highest priority)
      for (final cre in commentRe) {
        final m = cre.matchAsPrefix(line, pos);
        if (m != null) {
          spans.add(_span(m.group(0)!, AppTheme.codeComment));
          pos += m.group(0)!.length;
          matched = true;
          break;
        }
      }
      if (matched) continue;

      // Try string pattern
      if (strRe != null) {
        final m = strRe.matchAsPrefix(line, pos);
        if (m != null) {
          spans.add(_span(m.group(0)!, AppTheme.codeString));
          pos += m.group(0)!.length;
          continue;
        }
      }

      // Try template literals
      if (tplRe != null) {
        final m = tplRe.matchAsPrefix(line, pos);
        if (m != null) {
          spans.add(_span(m.group(0)!, AppTheme.codeType));
          pos += m.group(0)!.length;
          continue;
        }
      }

      // Try number patterns
      final numRe = RegExp(r'\b0[xX][0-9a-fA-F]+\b|\b\d+(\.\d+)?([eE][+-]?\d+)?\b');
      final numM = numRe.matchAsPrefix(line, pos);
      if (numM != null) {
        spans.add(_span(numM.group(0)!, AppTheme.codeLiteral));
        pos += numM.group(0)!.length;
        continue;
      }

      // Try function calls: word(
      final fnRe = RegExp(r'\b([a-zA-Z_]\w*)\s*(?=\()');
      final fnM = fnRe.matchAsPrefix(line, pos);
      if (fnM != null && fnM.group(1) != null && !allK.contains(fnM.group(1))) {
        spans.add(_span(fnM.group(0)!, AppTheme.codeFunction));
        pos += fnM.group(0)!.length;
        continue;
      }

      // Type annotations
      if (language == 'dart' || language == 'typescript' || language == 'kotlin' || language == 'swift') {
        final tpRe = RegExp(r'(?<=:\s*)([A-Z]\w*)');
        final tpM = tpRe.matchAsPrefix(line, pos);
        if (tpM != null) {
          spans.add(_span(tpM.group(0)!, AppTheme.codeType));
          pos += tpM.group(0)!.length;
          continue;
        }
      }

      // HTML/XML tags
      if (language == 'html' || language == 'xml') {
        final tagM = RegExp(r'<(/)?(\w+)').matchAsPrefix(line, pos);
        if (tagM != null) {
          spans.add(_span(tagM.group(0)!, AppTheme.codeKeyword));
          pos += tagM.group(0)!.length;
          continue;
        }
        final attrM = RegExp(r'\b([a-zA-Z-]+)=\s*["\']').matchAsPrefix(line, pos);
        if (attrM != null) {
          spans.add(_span(attrM.group(0)!, AppTheme.codeFunction));
          pos += attrM.group(0)!.length;
          continue;
        }
      }

      // CSS properties
      if (language == 'css') {
        final cssM = RegExp(r'\b([a-zA-Z-]+)\s*:').matchAsPrefix(line, pos);
        if (cssM != null) {
          spans.add(_span(cssM.group(0)!, AppTheme.codeFunction));
          pos += cssM.group(0)!.length;
          continue;
        }
      }

      // Markdown
      if (language == 'markdown') {
        if (RegExp(r'^#{1,6}\s').matchAsPrefix(line, pos) != null) {
          spans.add(_span(line.substring(pos), AppTheme.codeKeyword));
          pos = line.length;
          continue;
        }
        final boldM = RegExp(r'\*\*.*?\*\*|__.*?__').matchAsPrefix(line, pos);
        if (boldM != null) { spans.add(_span(boldM.group(0)!, AppTheme.codeFunction)); pos += boldM.group(0)!.length; continue; }
        final codeM = RegExp(r'`[^`]+`').matchAsPrefix(line, pos);
        if (codeM != null) { spans.add(_span(codeM.group(0)!, AppTheme.codeString)); pos += codeM.group(0)!.length; continue; }
      }

      // YAML keys
      if (language == 'yaml') {
        final ykM = RegExp(r'^[\s-]*([a-zA-Z_]\w*):').matchAsPrefix(line, pos);
        if (ykM != null) { spans.add(_span(ykM.group(0)!, AppTheme.codeFunction)); pos += ykM.group(0)!.length; continue; }
      }

      // JSON keys
      if (language == 'json') {
        final jkM = RegExp(r'"([^"]+)"\s*:').matchAsPrefix(line, pos);
        if (jkM != null) { spans.add(_span(jkM.group(0)!, AppTheme.codeFunction)); pos += jkM.group(0)!.length; continue; }
      }

      // Operators & punctuation
      final opM = RegExp(r'[+-/*%=<>!&|^~]+').matchAsPrefix(line, pos);
      if (opM != null) { spans.add(_span(opM.group(0)!, AppTheme.codeOperator)); pos += opM.group(0)!.length; continue; }

      final punctM = RegExp(r'[{}()\[\],.;:]').matchAsPrefix(line, pos);
      if (punctM != null) { spans.add(_span(punctM.group(0)!, AppTheme.textSecondary)); pos += punctM.group(0)!.length; continue; }

      // Collect non-matching chars as a word
      final start = pos;
      while (pos < line.length) {
        if (RegExp(r'[\s{}()\[\],.;:+\-/*%=<>!&|^~]').hasMatch(line[pos])) break;
        pos++;
      }
      if (start == pos) { pos++; continue; }
      final word = line.substring(start, pos);
      Color color = AppTheme.textPrimary;
      FontWeight weight = FontWeight.normal;
      if (allK.contains(word)) { color = AppTheme.codeKeyword; weight = FontWeight.w500; }
      else if (blt.contains(word)) { color = AppTheme.codeFunction; }
      else if (RegExp(r'^[A-Z]\w*').hasMatch(word)) { color = AppTheme.codeType; }

      spans.add(TextSpan(
        text: word,
        style: TextStyle(color: color, fontFamily: AppTheme.fontCode, fontWeight: weight),
      ));
    }
    return spans.isEmpty ? [const TextSpan(text: '')] : spans;
  }

  static TextSpan _span(String text, Color color) => TextSpan(
    text: text,
    style: TextStyle(color: color, fontFamily: AppTheme.fontCode),
  );
}

// ── Editor Screen ───────────────────────────────────────────────────────────

class EditorScreen extends StatefulWidget {
  final String? projectId, initialFilePath, initialContent, fileName, language;
  final bool readOnly;

  const EditorScreen({
    super.key, this.projectId, this.initialFilePath, this.initialContent,
    this.fileName, this.language, this.readOnly = false,
  });

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final List<_OpenTab> _tabs = [];
  int _activeTabIndex = 0;
  final _tabScroll = ScrollController();
  final _editorScroll = ScrollController();
  final _lineScroll = ScrollController();
  final _searchCtrl = TextEditingController();
  final _replaceCtrl = TextEditingController();
  final _gotoCtrl = TextEditingController();

  bool _showLineNumbers = true;
  bool _showSearch = false;
  bool _showAi = false;
  double _fontSize = Defaults.editorFontSize;
  bool _searchCase = false;
  bool _searchRegex = false;
  int _matchCount = 0, _matchIdx = 0;

  final Map<String, List<String>> _undo = {};
  final Map<String, List<String>> _redo = {};
  int? _bracketLine;

  _OpenTab? get _active => _tabs.isEmpty ? null : _tabs[_activeTabIndex.clamp(0, _tabs.length - 1)];

  @override
  void initState() {
    super.initState();
    _editorScroll.addListener(() {
      if (_lineScroll.hasClients) _lineScroll.jumpTo(_editorScroll.offset);
    });
    unawaited(_openInitialFile());
  }

  Future<void> _openInitialFile() async {
    final filePath = widget.initialFilePath;
    final fileName = widget.fileName ?? (filePath == null ? 'untitled' : p.basename(filePath));
    var content = widget.initialContent;
    Object? readError;
    if (content == null && filePath != null && filePath != 'untitled') {
      try {
        final file = File(filePath);
        final exists = await file.exists();
        content = exists ? await file.readAsString() : '';
      } on Object catch (error) {
        readError = error;
        content = '';
      }
    }
    if (!mounted) return;
    _open(filePath ?? 'untitled', fileName, content ?? '', widget.language, widget.readOnly);
    if (readError != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not read "$fileName": $readError'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: AppTheme.error,
          ),
        );
      });
    }
  }

  @override
  void dispose() {
    for (final t in _tabs) t.dispose();
    _tabScroll.dispose(); _editorScroll.dispose(); _lineScroll.dispose();
    _searchCtrl.dispose(); _replaceCtrl.dispose(); _gotoCtrl.dispose();
    super.dispose();
  }

  // ── Tab Management ──────────────────────────────────────────────────

  void _open(String path, String name, String content, [String? lang, bool ro = false]) {
    if (_tabs.indexWhere((t) => t.filePath == path) case final i when i != -1) {
      setState(() => _activeTabIndex = i);
      _focus(); return;
    }
    final language = lang ?? SyntaxHighlighter.detectLanguage(name);
    final ctrl = TextEditingController(text: content);
    final fn = FocusNode();
    ctrl.addListener(() {
      final tab = _tabs.firstWhere((t) => t.controller == ctrl, orElse: () => _tabs.first);
      final mod = tab.originalContent != ctrl.text;
      if (mod != tab.isModified) setState(() => tab.isModified = mod);
      _updateCursor(tab);
    });
    final tab = _OpenTab(
      id: 't${DateTime.now().millisecondsSinceEpoch}', fileName: name, filePath: path,
      language: language, controller: ctrl, focusNode: fn,
      originalContent: content, readOnly: ro,
    );
    setState(() { _tabs.add(tab); _activeTabIndex = _tabs.length - 1; });
    _undo[tab.id] = [content]; _redo[tab.id] = [];
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_tabScroll.hasClients) _tabScroll.animateTo(_tabScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    });
  }

  void _close(int i) {
    if (i < 0 || i >= _tabs.length) return;
    if (_tabs[i].isModified) { _unsaved(i); return; }
    _remove(i);
  }

  void _remove(int i) {
    final t = _tabs[i]; _undo.remove(t.id); _redo.remove(t.id); t.dispose();
    setState(() {
      _tabs.removeAt(i);
      if (_activeTabIndex >= i && _activeTabIndex > 0) _activeTabIndex--;
      if (_tabs.isEmpty) { _open('untitled', 'untitled', ''); _activeTabIndex = 0; }
      if (_activeTabIndex >= _tabs.length) _activeTabIndex = _tabs.length - 1;
    });
  }

  void _closeOthers(int keep) {
    for (int i = _tabs.length - 1; i >= 0; i--) if (i != keep) _remove(i);
  }

  void _closeAll() { for (int i = _tabs.length - 1; i >= 0; i--) _remove(i); }

  void _focus() => Future.delayed(const Duration(milliseconds: 50), () => _active?.focusNode.requestFocus());

  void _unsaved(int i) => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Unsaved Changes', style: TextStyle(color: AppTheme.textPrimary)),
      content: Text('"${_tabs[i].fileName}" has unsaved changes. Close without saving?',
          style: const TextStyle(color: AppTheme.textSecondary)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        TextButton(onPressed: () { Navigator.pop(ctx); _remove(i); },
            child: const Text('Discard', style: TextStyle(color: AppTheme.error))),
      ],
    ),
  );

  void _tabMenu(int i, Offset pos) => showMenu(
    context: context,
    position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx + 100, pos.dy),
    color: AppTheme.surface,
    items: [
      _menuItem('Close', () => _close(i)),
      _menuItem('Close Others', () => _closeOthers(i)),
      _menuItem('Close All', _closeAll),
      const PopupMenuDivider(),
      PopupMenuItem(child: Text(_tabs[i].filePath, style: const TextStyle(color: AppTheme.textTertiary, fontSize: 11))),
    ],
  );

  PopupMenuItem _menuItem(String label, VoidCallback onTap) => PopupMenuItem(
    onTap: () => Future.delayed(const Duration(milliseconds: 50), onTap),
    child: Text(label, style: const TextStyle(color: AppTheme.textPrimary)),
  );

  // ── Cursor ──────────────────────────────────────────────────────────

  void _updateCursor(_OpenTab tab) {
    final text = tab.controller.text;
    final sel = tab.controller.selection;
    if (!sel.isValid || sel.baseOffset < 0) return;
    final up = text.substring(0, sel.baseOffset.clamp(0, text.length));
    final ln = up.isEmpty ? 1 : '\n'.allMatches(up).length + 1;
    final lastNl = up.lastIndexOf('\n');
    final col = lastNl == -1 ? up.length + 1 : up.length - lastNl;
    if (mounted) setState(() { tab.cursorLine = ln; tab.cursorColumn = col; });
  }

  // ── Undo / Redo ─────────────────────────────────────────────────────

  void _undoFn() {
    final t = _active; if (t == null) return;
    final s = _undo[t.id]; if (s == null || s.length <= 1) return;
    _redo.putIfAbsent(t.id, () => []).add(s.removeLast());
    t.controller.text = s.last;
    t.controller.selection = TextSelection.collapsed(offset: s.last.length);
    HapticFeedback.lightImpact();
  }

  void _redoFn() {
    final t = _active; if (t == null) return;
    final s = _redo[t.id]; if (s == null || s.isEmpty) return;
    _undo.putIfAbsent(t.id, () => []).add(s.removeLast());
    t.controller.text = (_undo[t.id] ?? []).last;
    t.controller.selection = TextSelection.collapsed(offset: t.controller.text.length);
    HapticFeedback.lightImpact();
  }

  void _pushUndo() {
    final t = _active; if (t == null) return;
    _undo.putIfAbsent(t.id, () => []).add(t.controller.text);
    if ((_undo[t.id] ?? []).length > 50) _undo[t.id]!.removeAt(0);
    _redo[t.id]?.clear();
  }

  // ── Search & Replace ────────────────────────────────────────────────

  void _toggleSearch() {
    setState(() { _showSearch = !_showSearch; if (!_showSearch) _clearSearch(); });
  }

  void _search() {
    final q = _searchCtrl.text, t = _active;
    if (t == null || q.isEmpty) { setState(() => _matchCount = _matchIdx = 0); return; }
    try {
      final pat = _searchRegex ? q : RegExp.escape(q);
      final re = RegExp(pat, caseSensitive: _searchCase);
      final ms = re.allMatches(t.controller.text).toList();
      setState(() { _matchCount = ms.length; _matchIdx = ms.isNotEmpty ? 1 : 0; });
    } catch (_) { setState(() => _matchCount = _matchIdx = 0); }
  }

  void _findNext() {
    if (_matchCount == 0) return;
    final t = _active; if (t == null) return;
    setState(() => _matchIdx = (_matchIdx % _matchCount) + 1);
    _focus();
  }

  void _findPrev() {
    if (_matchCount == 0) return;
    final t = _active; if (t == null) return;
    setState(() => _matchIdx = _matchIdx <= 1 ? _matchCount : _matchIdx - 1);
    _focus();
  }

  void _replaceOne() {
    final t = _active; if (t == null || _matchCount == 0) return;
    _pushUndo();
    try {
      final pat = _searchRegex ? _searchCtrl.text : RegExp.escape(_searchCtrl.text);
      final re = RegExp(pat, caseSensitive: _searchCase);
      final ms = re.allMatches(t.controller.text).toList();
      if (_matchIdx > 0 && _matchIdx <= ms.length) {
        final m = ms[_matchIdx - 1];
        final r = _replaceCtrl.text;
        t.controller.text = t.controller.text.substring(0, m.start) + r + t.controller.text.substring(m.end);
        t.controller.selection = TextSelection.collapsed(offset: m.start + r.length);
      }
    } catch (_) {}
    _search();
  }

  void _replaceAll() {
    final t = _active; if (t == null) return;
    _pushUndo();
    try {
      final pat = _searchRegex ? _searchCtrl.text : RegExp.escape(_searchCtrl.text);
      final newText = t.controller.text.replaceAll(RegExp(pat, caseSensitive: _searchCase), _replaceCtrl.text);
      if (newText != t.controller.text) {
        t.controller.text = newText;
        t.controller.selection = const TextSelection.collapsed(offset: 0);
      }
    } catch (_) {}
    _search();
  }

  void _clearSearch() { _matchCount = _matchIdx = 0; }

  // ── Format ──────────────────────────────────────────────────────────

  void _format() {
    final t = _active; if (t == null) return;
    _pushUndo();
    final lines = t.controller.text.split('\n');
    final indent = '  ';
    final buf = StringBuffer();
    int level = 0;
    for (int i = 0; i < lines.length; i++) {
      final tr = lines[i].trim();
      if (tr.startsWith('}') || tr.startsWith(']') || tr.startsWith(')') ||
          tr == 'end' || tr.startsWith('elif ') || tr == 'else' || tr == 'done' || tr == 'fi') {
        level = (level - 1).clamp(0, 100);
      }
      if (tr.isNotEmpty) { buf.write(indent * level); buf.write(tr); }
      if (i < lines.length - 1) buf.write('\n');
      if (tr.endsWith('{') || tr.endsWith('[') || tr.endsWith('(') || tr.endsWith(':') ||
          ((t.language == 'shell' || t.language == 'yaml') && tr.endsWith('|'))) {
        level++;
      }
      final open = '{[("""\'\''.allMatches(tr).length;
      final close = '}])"""\'\''.allMatches(tr).length;
      if (open < close) level = (level - (close - open)).clamp(0, 100);
    }
    t.controller.text = buf.toString();
    HapticFeedback.mediumImpact();
  }

  // ── Go To Line ──────────────────────────────────────────────────────

  void _showGoto() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surface,
        title: const Text('Go to Line', style: TextStyle(color: AppTheme.textPrimary)),
        content: TextField(controller: _gotoCtrl, keyboardType: TextInputType.number,
          style: const TextStyle(color: AppTheme.textPrimary),
          decoration: const InputDecoration(hintText: 'Line number', hintStyle: TextStyle(color: AppTheme.textTertiary)),
          autofocus: true, onSubmitted: (_) { _goto(); Navigator.pop(ctx); }),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () { _goto(); Navigator.pop(ctx); }, child: const Text('Go')),
        ],
      ),
    );
  }

  void _goto() {
    final t = _active, n = int.tryParse(_gotoCtrl.text);
    if (t == null || n == null || n < 1) return;
    final lines = t.controller.text.split('\n');
    if (n > lines.length) return;
    int off = 0;
    for (int i = 0; i < n - 1; i++) off += lines[i].length + 1;
    t.controller.selection = TextSelection.collapsed(offset: off);
    t.focusNode.requestFocus();
    _gotoCtrl.clear();
  }

  // ── Bracket Match ───────────────────────────────────────────────────

  void _bracketMatch() {
    final t = _active; if (t == null) return;
    final text = t.controller.text, pos = t.controller.selection.start;
    if (pos <= 0 || pos > text.length) { setState(() => _bracketLine = null); return; }
    final c = text[pos - 1];
    const o = '({[<', cl = ')}]>';
    int? ml;
    if (o.contains(c)) {
      final ci = cl[o.indexOf(c)];
      int d = 1;
      for (int i = pos; i < text.length; i++) {
        if (text[i] == c) d++; if (text[i] == ci) d--;
        if (d == 0) { ml = '\n'.allMatches(text.substring(0, i)).length + 1; break; }
      }
    } else if (cl.contains(c)) {
      final oi = o[cl.indexOf(c)];
      int d = 1;
      for (int i = pos - 2; i >= 0; i--) {
        if (text[i] == c) d++; if (text[i] == oi) d--;
        if (d == 0) { ml = '\n'.allMatches(text.substring(0, i)).length + 1; break; }
      }
    }
    setState(() => _bracketLine = ml);
  }

  // ── Save ────────────────────────────────────────────────────────────

  void _save() {
    unawaited(_saveActiveFile());
  }

  Future<void> _saveActiveFile() async {
    final t = _active; if (t == null) return;
    if (t.readOnly) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${t.fileName}" is read-only'), behavior: SnackBarBehavior.floating),
      );
      return;
    }
    try {
      if (t.filePath.trim().isEmpty || t.filePath == 'untitled') {
        throw StateError('This tab has no phone file path yet.');
      }
      await File(t.filePath).writeAsString(t.controller.text);
      if (!mounted) return;
      setState(() { t.originalContent = t.controller.text; t.isModified = false; });
      HapticFeedback.mediumImpact();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${t.fileName}" saved to phone'), duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating, backgroundColor: AppTheme.surfaceHover,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
      );
    } on Object catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Save failed: $error'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppTheme.error,
        ),
      );
    }
  }

  // ── AI Panel ────────────────────────────────────────────────────────

  void _toggleAi() => setState(() => _showAi = !_showAi);
  String? _selectedCode() {
    final t = _active; if (t == null) return null;
    final s = t.controller.selection;
    return s.start == s.end ? null : t.controller.text.substring(s.start, s.end);
  }

  // ═══════════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(child: Column(children: [
        _tabBar(),
        _toolbar(),
        if (_showSearch) _searchPanel(),
        Expanded(child: _editorArea()),
        _statusBar(),
      ])),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _toggleAi, backgroundColor: AppTheme.primary,
        icon: const Icon(Icons.auto_awesome, color: Colors.white, size: 20),
        label: Text(_showAi ? 'Close AI' : 'Ask AI',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
      ),
    );
  }

  // ── Tab Bar ─────────────────────────────────────────────────────────

  Widget _tabBar() => Container(
    height: 42,
    decoration: BoxDecoration(color: AppTheme.backgroundElevated,
      border: Border(bottom: BorderSide(color: AppTheme.divider.withOpacity(0.8)))),
    child: Row(children: [
      SizedBox(width: 42, child: Center(
        child: Tooltip(
          message: '返回聊天',
          child: IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 19, color: AppTheme.textSecondary),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 36, height: 36),
          ),
        ),
      )),
      Expanded(child: ListView.builder(controller: _tabScroll, scrollDirection: Axis.horizontal,
        itemCount: _tabs.length, itemBuilder: (c, i) => _tabItem(i))),
      _td(),
      _tb(Icons.more_vert, 'More', _showOverflow),
    ]),
  );

  Widget _tabItem(int i) {
    final tab = _tabs[i], active = i == _activeTabIndex;
    return GestureDetector(
      onTap: () { setState(() => _activeTabIndex = i); _focus(); },
      onLongPressStart: (d) => _tabMenu(i, d.globalPosition),
      child: Container(constraints: const BoxConstraints(minWidth: 100, maxWidth: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          gradient: active ? AppTheme.primaryGradient : null,
          color: active ? null : AppTheme.backgroundElevated,
          border: Border(bottom: BorderSide(
            color: active ? AppTheme.accent : Colors.transparent, width: 2))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          _langIcon(tab.language), const SizedBox(width: 6),
          Flexible(child: Text(tab.fileName, overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.w400,
              color: active ? Colors.white : AppTheme.textSecondary))),
          if (tab.isModified) Container(width: 6, height: 6, margin: const EdgeInsets.only(left: 4),
            decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          InkWell(onTap: () => _close(i), borderRadius: BorderRadius.circular(8),
            child: Container(width: 18, height: 18, alignment: Alignment.center,
              child: Icon(Icons.close, size: 14, color: active ? Colors.white70 : AppTheme.textTertiary))),
        ]),
      ),
    );
  }

  Widget _langIcon(String l) {
    IconData i;
    switch (l) { case 'dart': i = Icons.flutter_dash; case 'python': i = Icons.code;
    case 'javascript': case 'typescript': i = Icons.javascript;
    case 'html': i = Icons.html; case 'css': i = Icons.style;
    case 'json': i = Icons.data_object; case 'markdown': i = Icons.text_snippet;
    default: i = Icons.insert_drive_file_outlined; }
    return Icon(i, size: 14, color: AppTheme.textTertiary);
  }

  void _showOverflow() => showMenu(
    context: context,
    position: RelativeRect.fromLTRB(MediaQuery.of(context).size.width - 40, 100, 0, 0),
    color: AppTheme.surface,
    items: [
      _mi(Icons.format_indent_increase, 'Format Code', _format),
      _mi(Icons.visibility, _showLineNumbers ? 'Hide Line Numbers' : 'Show Line Numbers',
        () => setState(() => _showLineNumbers = !_showLineNumbers)),
      _mi(Icons.format_size, 'Font Size', _showFontDlg),
      const PopupMenuDivider(),
      _mi(Icons.save, 'Save', _save),
      PopupMenuItem(
        onTap: () => Future.delayed(const Duration(milliseconds: 100), _closeAll),
        child: const Row(children: [Icon(Icons.close, size: 18, color: AppTheme.error), SizedBox(width: 10),
          Text('Close All Tabs', style: TextStyle(color: AppTheme.error))])),
    ],
  );

  PopupMenuItem _mi(IconData icon, String label, VoidCallback fn) => PopupMenuItem(
    onTap: () => Future.delayed(const Duration(milliseconds: 100), fn),
    child: Row(children: [Icon(icon, size: 18, color: AppTheme.textSecondary), const SizedBox(width: 10),
      Text(label, style: const TextStyle(color: AppTheme.textPrimary))]),
  );

  void _showFontDlg() => showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Font Size', style: TextStyle(color: AppTheme.textPrimary)),
      content: StatefulBuilder(builder: (ctx, ss) => Column(mainAxisSize: MainAxisSize.min, children: [
        Slider(value: _fontSize, min: 8, max: 24, divisions: 16, label: _fontSize.toStringAsFixed(0),
          activeColor: AppTheme.primary, inactiveColor: AppTheme.border,
          onChanged: (v) => ss(() => _fontSize = v)),
        Text('${_fontSize.toStringAsFixed(0)}px', style: const TextStyle(color: AppTheme.textSecondary)),
      ])),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done'))],
    ),
  );

  // ── Toolbar ─────────────────────────────────────────────────────────

  Widget _toolbar() => Container(
    height: 44,
    decoration: BoxDecoration(color: AppTheme.background,
      border: Border(bottom: BorderSide(color: AppTheme.divider.withOpacity(0.5)))),
    child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 4),
      children: [
        _tb(Icons.undo, 'Undo (Ctrl+Z)', _undoFn),
        _tb(Icons.redo, 'Redo (Ctrl+Y)', _redoFn),
        _td(),
        _tb(Icons.search, 'Search & Replace', _toggleSearch, isActive: _showSearch),
        _tb(Icons.format_indent_increase, 'Format Code', _format),
        _td(),
        _tb(Icons.format_list_numbered, 'Toggle Line Numbers',
          () => setState(() => _showLineNumbers = !_showLineNumbers), isActive: _showLineNumbers),
        _tb(Icons.arrow_downward, 'Go to Line', _showGoto),
        _tb(Icons.save, 'Save', _save),
      ]),
  );

  // ── Search Panel ────────────────────────────────────────────────────

  Widget _searchPanel() => Container(
    decoration: BoxDecoration(color: AppTheme.backgroundElevated,
      border: Border(bottom: BorderSide(color: AppTheme.divider.withOpacity(0.5)))),
    padding: const EdgeInsets.all(12),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: _sf(_searchCtrl, 'Search...', (_) => _search())),
        if (_matchCount > 0) Padding(padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text('$_matchIdx / $_matchCount', style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary))),
        _tb(Icons.keyboard_arrow_up, 'Previous', _findPrev),
        _tb(Icons.keyboard_arrow_down, 'Next', _findNext),
        _tb(Icons.close, 'Close', _toggleSearch),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _sf(_replaceCtrl, 'Replace...', (_) => _replaceOne())),
        _tb(Icons.find_replace, 'Replace', _replaceOne),
        _tb(Icons.crop_7_5, 'Replace All', _replaceAll),
      ]),
      const SizedBox(height: 8),
      Row(children: [
        _st('Case Sensitive', _searchCase, () { setState(() { _searchCase = !_searchCase; }); _search(); }),
        const SizedBox(width: 8),
        _st('Regex', _searchRegex, () { setState(() { _searchRegex = !_searchRegex; }); _search(); }),
      ]),
    ]),
  );

  Widget _sf(TextEditingController c, String h, ValueChanged<String>? onSub) => Container(
    height: 36, decoration: BoxDecoration(color: AppTheme.surfaceInput, borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border)),
    child: TextField(controller: c, style: const TextStyle(color: AppTheme.textPrimary, fontSize: 13, fontFamily: AppTheme.fontCode),
      decoration: InputDecoration(hintText: h, hintStyle: const TextStyle(color: AppTheme.textTertiary, fontSize: 13),
        border: InputBorder.none, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), isDense: true),
      textInputAction: TextInputAction.search, onSubmitted: onSub),
  );

  Widget _st(String label, bool active, VoidCallback onTap) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(6),
    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: active ? AppTheme.primary.withOpacity(0.15) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: active ? AppTheme.primary.withOpacity(0.5) : AppTheme.border)),
      child: Text(label, style: TextStyle(fontSize: 11, fontWeight: active ? FontWeight.w600 : FontWeight.w400,
        color: active ? AppTheme.primary : AppTheme.textTertiary))),
  );

  // ── Editor Area ─────────────────────────────────────────────────────

  Widget _editorArea() {
    final t = _active; if (t == null) return const SizedBox.shrink();
    return Row(children: [
      Expanded(child: Container(color: AppTheme.editorBackground,
        child: Row(children: [
          if (_showLineNumbers) _lineNumbers(t),
          if (_showLineNumbers) Container(width: 1, color: AppTheme.divider.withOpacity(0.3)),
          Expanded(child: _codeEditor(t)),
        ]))),
      if (_showAi) SizedBox(width: MediaQuery.of(context).size.width * 0.6,
        child: AiChatPanel(onClose: _toggleAi, currentCode: _selectedCode() ?? t.controller.text,
          fileName: t.fileName, language: t.language)),
    ]);
  }

  Widget _lineNumbers(_OpenTab tab) {
    final text = tab.controller.text;
    final lc = text.isEmpty ? 1 : '\n'.allMatches(text).length + 1;
    return Container(width: 48, color: AppTheme.editorGutter,
      child: ListView.builder(controller: _lineScroll, physics: const NeverScrollableScrollPhysics(),
        itemCount: lc, itemBuilder: (c, i) {
          final ln = i + 1, cur = ln == tab.cursorLine;
          return Container(height: _fontSize * 1.65, alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              color: cur ? AppTheme.editorActiveLine.withOpacity(0.5) : null,
              border: cur ? Border(right: BorderSide(color: AppTheme.primary.withOpacity(0.6), width: 2)) : null),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              _foldInd(i, text),
              Text('$ln', style: TextStyle(fontSize: _fontSize - 3,
                color: cur ? AppTheme.textSecondary : AppTheme.editorLineNumber.withOpacity(0.5),
                fontFamily: AppTheme.fontCode)),
            ]));
        }),
    );
  }

  Widget _foldInd(int i, String text) {
    final lines = text.split('\n');
    if (i >= lines.length) return const SizedBox(width: 12);
    final tr = lines[i].trim();
    IconData? ic;
    if (tr.endsWith('{') || tr.endsWith('[') || tr.endsWith('(') || tr.endsWith(':')) ic = Icons.keyboard_arrow_down;
    else if (tr.startsWith('}') || tr.startsWith(']') || tr.startsWith(')')) ic = Icons.keyboard_arrow_up;
    if (ic == null) return const SizedBox(width: 12);
    return SizedBox(width: 12, child: Icon(ic, size: 10, color: AppTheme.textTertiary.withOpacity(0.4)));
  }

  Widget _codeEditor(_OpenTab tab) => Container(color: AppTheme.editorBackground,
    child: Column(children: [
      if (_bracketLine != null) Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        color: AppTheme.accent.withOpacity(0.1),
        child: Text('Matching bracket at line $_bracketLine',
          style: TextStyle(fontSize: 10, color: AppTheme.accent.withOpacity(0.8), fontFamily: AppTheme.fontCode))),
      Expanded(child: SingleChildScrollView(controller: _editorScroll,
        child: SingleChildScrollView(scrollDirection: Axis.horizontal,
          child: Container(constraints: BoxConstraints(minWidth: _editorWidth()),
            child: TextField(
              controller: tab.controller, focusNode: tab.focusNode, maxLines: null,
              keyboardType: TextInputType.multiline, textInputAction: TextInputAction.newline,
              readOnly: tab.readOnly,
              style: TextStyle(fontSize: _fontSize, fontFamily: AppTheme.fontCode,
                color: AppTheme.textPrimary, height: 1.65, letterSpacing: 0.3),
              cursorColor: AppTheme.editorCursor, cursorWidth: 2, cursorRadius: const Radius.circular(1),
              decoration: const InputDecoration(border: InputBorder.none,
                contentPadding: EdgeInsets.only(left: 12, right: 12, top: 4, bottom: 4), isDense: true),
              onChanged: (_) { _updateCursor(tab); _bracketMatch(); },
              enableInteractiveSelection: true,
              selectionControls: materialTextSelectionControls,
              contextMenuBuilder: (ctx, es) => AdaptiveTextSelectionToolbar.buttonItems(
                anchors: es.contextMenuAnchors,
                buttonItems: [...es.contextMenuButtonItems,
                  ContextMenuButtonItem(label: 'Format Selection',
                    onPressed: () { es.hideToolbar(); _format(); }),
                  ContextMenuButtonItem(label: 'Ask AI',
                    onPressed: () { es.hideToolbar(); if (!_showAi) setState(() => _showAi = true); }),
                ]),
            ),
          ),
        ),
      )),
    ]),
  );

  double _editorWidth() {
    final w = MediaQuery.of(context).size.width;
    return w - (_showLineNumbers ? 49 : 0) - (_showAi ? w * 0.6 : 0);
  }

  // ── Status Bar ──────────────────────────────────────────────────────

  Widget _statusBar() {
    final t = _active; if (t == null) return const SizedBox.shrink();
    return Container(height: 28, padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(gradient: AppTheme.surfaceGradient,
        border: Border(top: BorderSide(color: AppTheme.divider.withOpacity(0.5)))),
      child: Row(children: [
        _si(Icons.my_location, 'Ln ${t.cursorLine}, Col ${t.cursorColumn}'),
        _sd(),
        _si(Icons.format_align_left, '${t.lineCount} lines, ${t.wordCount} words'),
        _sd(),
        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
          child: Text(SyntaxHighlighter.languageLabel(t.language).toUpperCase(),
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
              color: AppTheme.primary.withOpacity(0.9), fontFamily: AppTheme.fontCode))),
        _sd(),
        const _StatusItem(text: 'UTF-8'), _sd(),
        if (t.isModified) ...[
          Container(width: 8, height: 8, decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle)),
          const SizedBox(width: 4),
          const Text('Modified', style: TextStyle(fontSize: 10, color: AppTheme.accent, fontWeight: FontWeight.w500)),
        ],
        if (t.readOnly) Container(margin: const EdgeInsets.only(left: 8),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: AppTheme.warning.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
          child: const Text('READ-ONLY', style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.warning))),
        const Spacer(),
        Text('${t.charCount} chars', style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
      ]),
    );
  }

  Widget _si(IconData? i, String t) => _StatusItem(icon: i, text: t);
  Widget _sd() => Container(width: 1, height: 12, margin: const EdgeInsets.symmetric(horizontal: 8), color: AppTheme.divider);

  Widget _tb(IconData i, String tip, VoidCallback fn, {bool isActive = false}) => _TButton(icon: i, tooltip: tip, onPressed: fn, active: isActive);
  Widget _td() => Container(width: 1, height: 24, margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 10), color: AppTheme.divider);
}

// ── Reusable Widgets ────────────────────────────────────────────────────────

class _TButton extends StatelessWidget {
  final IconData icon; final String tooltip; final VoidCallback onPressed; final bool active;
  const _TButton({required this.icon, required this.tooltip, required this.onPressed, this.active = false});
  @override
  Widget build(BuildContext context) => Tooltip(message: tooltip, child: Material(color: Colors.transparent,
    child: InkWell(onTap: onPressed, borderRadius: BorderRadius.circular(6),
      child: Container(width: 36, height: 36, margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: active ? BoxDecoration(color: AppTheme.primary.withOpacity(0.15), borderRadius: BorderRadius.circular(6)) : null,
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: active ? AppTheme.primary : AppTheme.textSecondary)))),
  );
}

class _StatusItem extends StatelessWidget {
  final IconData? icon; final String text;
  const _StatusItem({this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    if (icon != null) Icon(icon, size: 12, color: AppTheme.textTertiary),
    if (icon != null) const SizedBox(width: 4),
    Text(text, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary, fontFamily: AppTheme.fontCode)),
  ]);
}
