import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart';
import 'package:json_ld_processor/src/context_processing.dart';
import 'package:json_ld_processor/src/expansion.dart';
import 'package:json_ld_processor/src/flatten.dart';
import 'package:json_ld_processor/src/normalize.dart';
import 'package:json_ld_processor/src/to_rdf.dart';

class JsonLdProcessor {
  // input: Map<String, dynamic>, List<Map>, String, RemoteDocument
  //context: Map<String, dynamic>, List<Map or String>, String
  static FutureOr<Map<String, dynamic>> compact(dynamic input,
      {dynamic context, JsonLdOptions? options}) {
    throw UnimplementedError();
  }

  static FutureOr<String> expand(dynamic input,
      {JsonLdOptions? options}) async {
    options ??= JsonLdOptions();
    dynamic parsableDoc;
    //2)
    Uri? documentUrl;
    if (input is RemoteDocument) {
      //4)
      documentUrl = input.documentUrl;
      if (input.document is String) {
        parsableDoc = jsonDecode(input.document);
      } else if (input.document is Map<String, dynamic>) {
        parsableDoc = input.document;
      } else {
        throw JsonLdError('Loading document failed');
      }
    }
    //3)
    else if (input is String) {
      //dereference URI
      throw UnimplementedError();
    } else if (input is Map<String, dynamic>) {
      parsableDoc = input;
    } else if (input is List) {
      parsableDoc = input;
    } else {
      throw Exception();
    }

    //5)
    var activeContext = Context(
        terms: {},
        options: options,
        baseIri: (input is RemoteDocument ? input.documentUrl : options.base) ??
            Uri(),
        originalBaseIri:
            (input is RemoteDocument ? input.documentUrl : options.base) ??
                Uri());

    //6)
    if (options.expandContext != null) {
      activeContext = await processContext(
          activeContext: activeContext,
          localContext: options.expandContext is Map &&
                  options.expandContext.containsKey('@context')
              ? options.expandContext['@context']
              : options.expandContext,
          baseUrl: activeContext.originalBaseIri);
    }
    //7)
    if (input is RemoteDocument && input.contextUrl != Uri()) {
      activeContext = await processContext(
          activeContext: activeContext,
          localContext: input.contextUrl,
          baseUrl: input.contextUrl);
    }

    //8) expand
    var expandedValue = await expandDoc(
        activeContext: activeContext,
        activeProperty: null,
        element: parsableDoc,
        baseUrl: documentUrl ?? options.base ?? Uri(),
        frameExpansion: options.frameExpansion,
        ordered: options.ordered,
        safeMode: options.safeMode);
    //8.1
    if (expandedValue is Map &&
        expandedValue.length == 1 &&
        expandedValue.containsKey('@graph')) {
      expandedValue = expandedValue['@graph'];
    }
    //8.2
    expandedValue ??= [];
    //8.3
    if (expandedValue is! List) {
      expandedValue = [expandedValue];
    }
    return jsonEncode(expandedValue);
  }

  static FutureOr<String> flatten(dynamic input,
      {dynamic context, JsonLdOptions? options}) async {
    options ??= JsonLdOptions();
    //2
    if (input is RemoteDocument) {
      input = input.document;
    }
    //3
    else if (input is String) {
      //TODO: Load doc to flatten
      throw UnimplementedError();
    }
    //4
    var expandedInput = await expand(input,
        options: JsonLdOptions(
            base: options.base,
            ordered: false,
            frameExpansion: options.frameExpansion,
            compactArrays: options.compactArrays,
            compactToRelative: options.compactToRelative,
            documentLoader: options.documentLoader,
            expandContext: options.expandContext,
            extractAllScripts: options.extractAllScripts,
            processingMode: options.processingMode,
            produceGeneralized: options.produceGeneralized,
            rdfDirection: options.rdfDirection,
            useNativeTypes: options.useNativeTypes,
            useRdfType: options.useRdfType,
            safeMode: options.safeMode));
    //5
    Map identifierMap = {};
    //6
    var flattenedOutput = flattenDoc(
        element: jsonDecode(expandedInput), ordered: options.ordered);
    //6.1
    if (context != null) {
      throw UnimplementedError('Compaction is not supported now');
    }
    //7
    return jsonEncode(flattenedOutput);
  }

  static FutureOr<Map<String, dynamic>> fromRdf(RdfDataset input,
      {JsonLdOptions? options}) {
    throw UnimplementedError();
  }

  static FutureOr<RdfDataset> toRdf(dynamic input,
      {JsonLdOptions? options}) async {
    options ??= JsonLdOptions();
    //2
    var expandedInput = await expand(input,
        options: JsonLdOptions(
            ordered: false,
            useRdfType: options.useRdfType,
            useNativeTypes: options.useNativeTypes,
            rdfDirection: options.rdfDirection,
            produceGeneralized: options.produceGeneralized,
            processingMode: options.processingMode,
            extractAllScripts: options.extractAllScripts,
            expandContext: options.expandContext,
            documentLoader: options.documentLoader,
            compactToRelative: options.compactToRelative,
            compactArrays: options.compactArrays,
            frameExpansion: options.frameExpansion,
            base: options.base,
            safeMode: options.safeMode));
    //3
    var dataset = RdfDataset(RdfGraph());
    //4
    var nodeMap = NodeMap();
    //5
    generateNodeMap(element: jsonDecode(expandedInput), nodeMap: nodeMap);
    //6
    await deserializeJsonLdToRdf(nodeMap, dataset,
        produceGeneralizedRdf: options.produceGeneralized,
        rdfDirection: options.rdfDirection);
    //7
    return dataset;
  }

  //input: RDFDataset, Map, String(= Url), RemoteDocument
  static FutureOr<String> normalize(dynamic input,
      {JsonLdOptions? options}) async {
    options ??= JsonLdOptions();

    if (input is! RdfDataset) {
      input = await toRdf(input, options: options);
    }
    return normalizeImpl(input);
  }
}

class RemoteDocument {
  final String _contentType;
  final Uri _contextUrl;
  dynamic document;
  final Uri _documentUrl;
  final String _profile;

  RemoteDocument(
      {String? contentType,
      Uri? contextUrl,
      required this.document,
      Uri? documentUrl,
      String? profile})
      : _contentType = contentType ?? '',
        _contextUrl = contextUrl ?? Uri(),
        _documentUrl = documentUrl ?? Uri(),
        _profile = profile ?? '';

  String get profile => _profile;

  Uri get documentUrl => _documentUrl;

  Uri get contextUrl => _contextUrl;

  String get contentType => _contentType;
}

class JsonLdOptions {
  final Uri? _base;
  final bool _compactArrays;
  final bool _compactToRelative;
  final Function(Uri url, LoadDocumentOptions? options) _documentLoader;
  final dynamic _expandContext;
  final bool _extractAllScripts;
  final bool _frameExpansion;
  final bool _ordered;
  final String _processingMode;
  final bool _produceGeneralized;
  final String? _rdfDirection;
  final bool _useNativeTypes;
  final bool _useRdfType;
  final bool _safeMode;

  JsonLdOptions(
      {Uri? base,
      bool compactArrays = true,
      bool compactToRelative = true,
      Function(Uri url, LoadDocumentOptions? options)? documentLoader,
      dynamic expandContext,
      bool extractAllScripts = false,
      bool frameExpansion = false,
      bool ordered = false,
      String processingMode = 'json-ld-1.1',
      bool produceGeneralized = true,
      String? rdfDirection,
      bool useNativeTypes = false,
      bool useRdfType = false,
      bool safeMode = false})
      : _base = base,
        _compactArrays = compactArrays,
        _compactToRelative = compactToRelative,
        _documentLoader = documentLoader ?? loadDocument,
        _expandContext = expandContext,
        _extractAllScripts = extractAllScripts,
        _frameExpansion = frameExpansion,
        _ordered = ordered,
        _processingMode = processingMode,
        _produceGeneralized = produceGeneralized,
        _rdfDirection = rdfDirection,
        _useNativeTypes = useNativeTypes,
        _useRdfType = useRdfType,
        _safeMode = safeMode;

  bool get useRdfType => _useRdfType;

  bool get useNativeTypes => _useNativeTypes;

  String? get rdfDirection => _rdfDirection;

  bool get produceGeneralized => _produceGeneralized;

  String get processingMode => _processingMode;

  bool get ordered => _ordered;

  bool get frameExpansion => _frameExpansion;

  bool get extractAllScripts => _extractAllScripts;

  dynamic get expandContext => _expandContext;

  bool get compactToRelative => _compactToRelative;

  bool get compactArrays => _compactArrays;

  Uri? get base => _base;

  Function(Uri url, LoadDocumentOptions? options) get documentLoader =>
      _documentLoader;

  bool get safeMode => _safeMode;
}

Future<RemoteDocument> loadDocument(
    Uri url, LoadDocumentOptions? options) async {
  var response =
      await get(url, headers: {'content-Type': 'application/ld+json'});

  if (response.statusCode == 301 ||
      response.statusCode == 302 ||
      response.statusCode == 303 ||
      response.statusCode == 307) {
    throw UnimplementedError('redirects are not supported now');
  }
  if (response.statusCode != 200) {
    throw JsonLdError('Document loading failed: ${response.statusCode}; $url');
  }

  String? contentType = response.headers['content-type'];
  if (contentType == null || !contentType.contains('json')) {
    if (response.headers.containsKey('link')) {
      var link = response.headers['link'];
      var split = link!.split(';');
      var resource = split.first.substring(1, split.first.length - 1);
      var newUri = url.resolve(resource);
      response =
          await get(newUri, headers: {'content-Type': 'application/ld+json'});
    } else {
      throw JsonLdError(
          'Document loading failed: ${response.statusCode}; $url');
    }
  }

  return RemoteDocument(document: jsonDecode(response.body));
}

class LoadDocumentOptions {
  final bool _extractAllScripts;
  final String? _profile;
  final List<String>? _requestProfile;

  LoadDocumentOptions(
      {bool extractAllScripts = false,
      String? profile,
      List<String>? requestProfile})
      : _extractAllScripts = extractAllScripts,
        _profile = profile,
        _requestProfile = requestProfile;

  List<String>? get requestProfile => _requestProfile;

  String? get profile => _profile;

  bool get extractAllScripts => _extractAllScripts;
}

class JsonLdError implements Exception {
  String message;
  JsonLdError(this.message);
  @override
  String toString() {
    return message;
  }
}

class RdfDataset {
  final RdfGraph _defaultGraph;
  late Map<String, RdfGraph> graphs;

  RdfDataset(RdfGraph defaultGraph) : _defaultGraph = defaultGraph {
    graphs = {'null': _defaultGraph};
  }

  RdfDataset.fromNQuad(String nquads) : _defaultGraph = RdfGraph() {
    graphs = {'null': _defaultGraph};
    var nquadList = nquads.split('\n');
    for (var entry in nquadList) {
      if (entry.trim().isEmpty) continue;
      var tripleString = entry.split(' ');
      if (tripleString[tripleString.length - 2].contains('\u0022')) {
        //no graph Name, Literal at last pos
        graphs['null']!.add(RdfTriple.fromString(entry));
      } else if (tripleString[2].contains('\u0022')) {
        //with graphName and literal
        String graphName = tripleString[tripleString.length - 2];
        if (graphName.startsWith('<')) {
          graphName = graphName.substring(1, graphName.length - 1);
        }
        if (graphs.containsKey(graphName)) {
          graphs[graphName]!.add(RdfTriple.fromString(entry));
        } else {
          add(graphName, RdfGraph([RdfTriple.fromString(entry)]));
        }
      } else if (tripleString.length == 4) {
        //no graphName -> defaultGraph
        graphs['null']!.add(RdfTriple.fromString(entry));
      } else if (tripleString.length == 5) {
        String graphName = tripleString[3];
        if (graphName.startsWith('<')) {
          graphName = graphName.substring(1, graphName.length - 1);
        }
        if (graphs.containsKey(graphName)) {
          graphs[graphName]!.add(RdfTriple.fromString(entry));
        } else {
          add(graphName, RdfGraph([RdfTriple.fromString(entry)]));
        }
      } else {
        throw Exception('no NQuad');
      }
    }
  }

  void add(String graphName, RdfGraph graph) {
    graphs[graphName] = graph;
  }

  RdfGraph get defaultGraph => _defaultGraph;

  @override
  String toString() {
    String graphString = '';
    graphs.forEach((key, value) {
      if (value.triple.isNotEmpty) {
        for (var t in value.triple) {
          graphString +=
              '$t ${key == 'null' ? '' : (key.startsWith('_:') ? '$key ' : '<$key> ')}.\n';
        }
      }
    });
    return graphString;
  }
}

class RdfGraph {
  late List<RdfTriple> triple;

  RdfGraph([List<RdfTriple>? triple]) {
    if (triple != null) {
      this.triple = triple;
    } else {
      this.triple = [];
    }
  }

  void add(RdfTriple triple) {
    this.triple.add(triple);
  }

  @override
  String toString() {
    return triple.toString();
  }
}

class RdfTriple {
  //IRI or Blank node
  late final String _subject;
  //IRI
  late final String _predicate;
  //IRI, Literal or Blank Node
  late final dynamic _object;

  RdfTriple(this._subject, this._predicate, this._object) {
    // if (_object is! String || _object is! RdfLiteral) {
    //   throw FormatException('Object must be String or RdfLiteral');
    // }
  }

  RdfTriple.fromString(String nquad) {
    var parts = nquad.split(' ');
    if (parts.length < 3) throw Exception('no nquad string');
    _predicate = parts[1].substring(1, parts[1].length - 1);
    _subject = parts[0].startsWith('_:')
        ? parts[0]
        : parts[0].substring(1, parts[0].length - 1);
    if (parts[2].startsWith('\u0022')) {
      if (parts[2].endsWith('\u0022') ||
          parts[2].contains('^^') ||
          parts[2].contains('@')) {
        _object = RdfLiteral.fromString(parts[2]);
      } else {
        int index = 3;
        String literal = '${parts[2]} ';
        while (true) {
          literal += parts[index];
          if (parts[index].contains('\u0022')) break;
          literal += ' ';
          index++;
        }
        _object = RdfLiteral.fromString(literal);
      }
    } else {
      _object = parts[2].startsWith('_:')
          ? parts[2]
          : parts[2].substring(1, parts[2].length - 1);
    }
  }

  dynamic get object => _object;

  String get predicate => _predicate;

  String get subject => _subject;

  @override
  String toString() {
    return '${_subject.startsWith('_:') ? _subject : '<$_subject>'} <$_predicate> ${_object is RdfLiteral ? _object.toString() : (_object is String && _object.startsWith('_:') ? _object : '<$_object>')}';
  }
}

class RdfLiteral {
  late final String _value;
  //if datatype is null, we assume xsd:string
  late final String? _datatype;
  late final String? _language;

  RdfLiteral(this._value, {String? datatype, String? language})
      : _datatype = datatype,
        _language = language;

  RdfLiteral.fromString(String literal) {
    if (literal.endsWith('\u0022')) {
      _value = literal.substring(1, literal.length - 1);
      _datatype = null;
      _language = null;
    } else {
      _value = literal.substring(1, literal.indexOf('\u0022', 2));
      if (literal.contains('^^')) {
        _datatype = literal.substring(
            literal.indexOf('^^<') + 3,
            literal.contains('@')
                ? literal.indexOf('@') - 1
                : literal.length - 1);
      } else {
        _datatype = null;
      }
      if (literal.contains('@')) {
        _language = literal.substring(literal.indexOf('@') + 1);
      } else {
        _language = null;
      }
    }
  }

  String? get language => _language;

  String? get datatype => _datatype;

  String get value => _value;

  @override
  String toString() {
    return '\u0022$_value\u0022${_datatype != null && _datatype != 'xsd:string' && _datatype != 'xsd:langString' ? '^^<$_datatype>' : ''}${_language != null ? '@$_language' : ''}';
  }
}