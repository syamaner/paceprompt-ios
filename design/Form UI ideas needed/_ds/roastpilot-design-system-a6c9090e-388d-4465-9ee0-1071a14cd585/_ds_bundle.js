/* @ds-bundle: {"namespace":"RoastPilotDS","components":[{"name":"AppFrame","sourcePath":"components/shared/AppFrame/AppFrame.jsx"},{"name":"ConnectionIndicator","sourcePath":"components/shared/ConnectionIndicator/ConnectionIndicator.jsx"},{"name":"LiveCurve","sourcePath":"components/shared/LiveCurve/LiveCurve.jsx"},{"name":"VerdictBadge","sourcePath":"components/shared/VerdictBadge/VerdictBadge.jsx"}],"sourceHashes":{"components/shared/AppFrame/AppFrame.jsx":"366dfde01381","components/shared/AppFrame/AppFrame.d.ts":"6543b43f8bd7","components/shared/AppFrame/AppFrame.prompt.md":"71c560bd4926","components/shared/ConnectionIndicator/ConnectionIndicator.jsx":"ffef00dbf2d9","components/shared/ConnectionIndicator/ConnectionIndicator.d.ts":"ce306e854a5b","components/shared/ConnectionIndicator/ConnectionIndicator.prompt.md":"ac38be5fd93f","components/shared/LiveCurve/LiveCurve.jsx":"97ab6a1821ff","components/shared/LiveCurve/LiveCurve.d.ts":"afbfbcfba0c3","components/shared/LiveCurve/LiveCurve.prompt.md":"b0cc3face74c","components/shared/VerdictBadge/VerdictBadge.jsx":"76709fbd0cf6","components/shared/VerdictBadge/VerdictBadge.d.ts":"8febcc0698b8","components/shared/VerdictBadge/VerdictBadge.prompt.md":"b4ab47910098"},"inlinedExternals":["clsx","tailwind-merge","uplot"],"builtBy":"cc-design-sync"} */
var RoastPilotDS = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __esm = (fn, res, err) => function __init() {
    if (err) throw err[0];
    try {
      return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
    } catch (e) {
      throw err = [e], e;
    }
  };
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // <define:import.meta.env>
  var init_define_import_meta_env = __esm({
    "<define:import.meta.env>"() {
    }
  });

  // shim:react-shim
  var require_react_shim = __commonJS({
    "shim:react-shim"(exports, module) {
      init_define_import_meta_env();
      var R = window.React;
      function np(p, k) {
        var o = {};
        for (var x in p) if (x !== "children") o[x] = p[x];
        if (k !== void 0) o.key = k;
        return o;
      }
      function jsx(t, p, k) {
        var c = p && p.children;
        return c === void 0 ? R.createElement(t, np(p, k)) : R.createElement(t, np(p, k), c);
      }
      function jsxs(t, p, k) {
        return R.createElement.apply(R, [t, np(p, k)].concat(p.children));
      }
      module.exports = R;
      module.exports.jsx = jsx;
      module.exports.jsxs = jsxs;
      module.exports.jsxDEV = function(t, p, k, s) {
        return (s ? jsxs : jsx)(t, p, k);
      };
      module.exports.Fragment = R.Fragment;
    }
  });

  // web/ds-entry.tsx
  var ds_entry_exports = {};
  __export(ds_entry_exports, {
    AppFrame: () => AppFrame,
    ConnectionIndicator: () => ConnectionIndicator,
    LiveCurve: () => LiveCurve,
    VerdictBadge: () => VerdictBadge
  });
  init_define_import_meta_env();

  // web/src/components/shared/AppFrame.tsx
  init_define_import_meta_env();

  // web/src/lib/cn.ts
  init_define_import_meta_env();

  // web/node_modules/clsx/dist/clsx.mjs
  init_define_import_meta_env();
  function r(e) {
    var t, f, n = "";
    if ("string" == typeof e || "number" == typeof e) n += e;
    else if ("object" == typeof e) if (Array.isArray(e)) {
      var o = e.length;
      for (t = 0; t < o; t++) e[t] && (f = r(e[t])) && (n && (n += " "), n += f);
    } else for (f in e) e[f] && (n && (n += " "), n += f);
    return n;
  }
  function clsx() {
    for (var e, t, f = 0, n = "", o = arguments.length; f < o; f++) (e = arguments[f]) && (t = r(e)) && (n && (n += " "), n += t);
    return n;
  }

  // web/node_modules/tailwind-merge/dist/bundle-mjs.mjs
  init_define_import_meta_env();
  var CLASS_PART_SEPARATOR = "-";
  var createClassGroupUtils = (config) => {
    const classMap = createClassMap(config);
    const {
      conflictingClassGroups,
      conflictingClassGroupModifiers
    } = config;
    const getClassGroupId = (className) => {
      const classParts = className.split(CLASS_PART_SEPARATOR);
      if (classParts[0] === "" && classParts.length !== 1) {
        classParts.shift();
      }
      return getGroupRecursive(classParts, classMap) || getGroupIdForArbitraryProperty(className);
    };
    const getConflictingClassGroupIds = (classGroupId, hasPostfixModifier) => {
      const conflicts = conflictingClassGroups[classGroupId] || [];
      if (hasPostfixModifier && conflictingClassGroupModifiers[classGroupId]) {
        return [...conflicts, ...conflictingClassGroupModifiers[classGroupId]];
      }
      return conflicts;
    };
    return {
      getClassGroupId,
      getConflictingClassGroupIds
    };
  };
  var getGroupRecursive = (classParts, classPartObject) => {
    if (classParts.length === 0) {
      return classPartObject.classGroupId;
    }
    const currentClassPart = classParts[0];
    const nextClassPartObject = classPartObject.nextPart.get(currentClassPart);
    const classGroupFromNextClassPart = nextClassPartObject ? getGroupRecursive(classParts.slice(1), nextClassPartObject) : void 0;
    if (classGroupFromNextClassPart) {
      return classGroupFromNextClassPart;
    }
    if (classPartObject.validators.length === 0) {
      return void 0;
    }
    const classRest = classParts.join(CLASS_PART_SEPARATOR);
    return classPartObject.validators.find(({
      validator
    }) => validator(classRest))?.classGroupId;
  };
  var arbitraryPropertyRegex = /^\[(.+)\]$/;
  var getGroupIdForArbitraryProperty = (className) => {
    if (arbitraryPropertyRegex.test(className)) {
      const arbitraryPropertyClassName = arbitraryPropertyRegex.exec(className)[1];
      const property = arbitraryPropertyClassName?.substring(0, arbitraryPropertyClassName.indexOf(":"));
      if (property) {
        return "arbitrary.." + property;
      }
    }
  };
  var createClassMap = (config) => {
    const {
      theme,
      prefix
    } = config;
    const classMap = {
      nextPart: /* @__PURE__ */ new Map(),
      validators: []
    };
    const prefixedClassGroupEntries = getPrefixedClassGroupEntries(Object.entries(config.classGroups), prefix);
    prefixedClassGroupEntries.forEach(([classGroupId, classGroup]) => {
      processClassesRecursively(classGroup, classMap, classGroupId, theme);
    });
    return classMap;
  };
  var processClassesRecursively = (classGroup, classPartObject, classGroupId, theme) => {
    classGroup.forEach((classDefinition) => {
      if (typeof classDefinition === "string") {
        const classPartObjectToEdit = classDefinition === "" ? classPartObject : getPart(classPartObject, classDefinition);
        classPartObjectToEdit.classGroupId = classGroupId;
        return;
      }
      if (typeof classDefinition === "function") {
        if (isThemeGetter(classDefinition)) {
          processClassesRecursively(classDefinition(theme), classPartObject, classGroupId, theme);
          return;
        }
        classPartObject.validators.push({
          validator: classDefinition,
          classGroupId
        });
        return;
      }
      Object.entries(classDefinition).forEach(([key, classGroup2]) => {
        processClassesRecursively(classGroup2, getPart(classPartObject, key), classGroupId, theme);
      });
    });
  };
  var getPart = (classPartObject, path) => {
    let currentClassPartObject = classPartObject;
    path.split(CLASS_PART_SEPARATOR).forEach((pathPart) => {
      if (!currentClassPartObject.nextPart.has(pathPart)) {
        currentClassPartObject.nextPart.set(pathPart, {
          nextPart: /* @__PURE__ */ new Map(),
          validators: []
        });
      }
      currentClassPartObject = currentClassPartObject.nextPart.get(pathPart);
    });
    return currentClassPartObject;
  };
  var isThemeGetter = (func) => func.isThemeGetter;
  var getPrefixedClassGroupEntries = (classGroupEntries, prefix) => {
    if (!prefix) {
      return classGroupEntries;
    }
    return classGroupEntries.map(([classGroupId, classGroup]) => {
      const prefixedClassGroup = classGroup.map((classDefinition) => {
        if (typeof classDefinition === "string") {
          return prefix + classDefinition;
        }
        if (typeof classDefinition === "object") {
          return Object.fromEntries(Object.entries(classDefinition).map(([key, value]) => [prefix + key, value]));
        }
        return classDefinition;
      });
      return [classGroupId, prefixedClassGroup];
    });
  };
  var createLruCache = (maxCacheSize) => {
    if (maxCacheSize < 1) {
      return {
        get: () => void 0,
        set: () => {
        }
      };
    }
    let cacheSize = 0;
    let cache = /* @__PURE__ */ new Map();
    let previousCache = /* @__PURE__ */ new Map();
    const update = (key, value) => {
      cache.set(key, value);
      cacheSize++;
      if (cacheSize > maxCacheSize) {
        cacheSize = 0;
        previousCache = cache;
        cache = /* @__PURE__ */ new Map();
      }
    };
    return {
      get(key) {
        let value = cache.get(key);
        if (value !== void 0) {
          return value;
        }
        if ((value = previousCache.get(key)) !== void 0) {
          update(key, value);
          return value;
        }
      },
      set(key, value) {
        if (cache.has(key)) {
          cache.set(key, value);
        } else {
          update(key, value);
        }
      }
    };
  };
  var IMPORTANT_MODIFIER = "!";
  var createParseClassName = (config) => {
    const {
      separator,
      experimentalParseClassName
    } = config;
    const isSeparatorSingleCharacter = separator.length === 1;
    const firstSeparatorCharacter = separator[0];
    const separatorLength = separator.length;
    const parseClassName = (className) => {
      const modifiers = [];
      let bracketDepth = 0;
      let modifierStart = 0;
      let postfixModifierPosition;
      for (let index = 0; index < className.length; index++) {
        let currentCharacter = className[index];
        if (bracketDepth === 0) {
          if (currentCharacter === firstSeparatorCharacter && (isSeparatorSingleCharacter || className.slice(index, index + separatorLength) === separator)) {
            modifiers.push(className.slice(modifierStart, index));
            modifierStart = index + separatorLength;
            continue;
          }
          if (currentCharacter === "/") {
            postfixModifierPosition = index;
            continue;
          }
        }
        if (currentCharacter === "[") {
          bracketDepth++;
        } else if (currentCharacter === "]") {
          bracketDepth--;
        }
      }
      const baseClassNameWithImportantModifier = modifiers.length === 0 ? className : className.substring(modifierStart);
      const hasImportantModifier = baseClassNameWithImportantModifier.startsWith(IMPORTANT_MODIFIER);
      const baseClassName = hasImportantModifier ? baseClassNameWithImportantModifier.substring(1) : baseClassNameWithImportantModifier;
      const maybePostfixModifierPosition = postfixModifierPosition && postfixModifierPosition > modifierStart ? postfixModifierPosition - modifierStart : void 0;
      return {
        modifiers,
        hasImportantModifier,
        baseClassName,
        maybePostfixModifierPosition
      };
    };
    if (experimentalParseClassName) {
      return (className) => experimentalParseClassName({
        className,
        parseClassName
      });
    }
    return parseClassName;
  };
  var sortModifiers = (modifiers) => {
    if (modifiers.length <= 1) {
      return modifiers;
    }
    const sortedModifiers = [];
    let unsortedModifiers = [];
    modifiers.forEach((modifier) => {
      const isArbitraryVariant = modifier[0] === "[";
      if (isArbitraryVariant) {
        sortedModifiers.push(...unsortedModifiers.sort(), modifier);
        unsortedModifiers = [];
      } else {
        unsortedModifiers.push(modifier);
      }
    });
    sortedModifiers.push(...unsortedModifiers.sort());
    return sortedModifiers;
  };
  var createConfigUtils = (config) => ({
    cache: createLruCache(config.cacheSize),
    parseClassName: createParseClassName(config),
    ...createClassGroupUtils(config)
  });
  var SPLIT_CLASSES_REGEX = /\s+/;
  var mergeClassList = (classList, configUtils) => {
    const {
      parseClassName,
      getClassGroupId,
      getConflictingClassGroupIds
    } = configUtils;
    const classGroupsInConflict = [];
    const classNames = classList.trim().split(SPLIT_CLASSES_REGEX);
    let result = "";
    for (let index = classNames.length - 1; index >= 0; index -= 1) {
      const originalClassName = classNames[index];
      const {
        modifiers,
        hasImportantModifier,
        baseClassName,
        maybePostfixModifierPosition
      } = parseClassName(originalClassName);
      let hasPostfixModifier = Boolean(maybePostfixModifierPosition);
      let classGroupId = getClassGroupId(hasPostfixModifier ? baseClassName.substring(0, maybePostfixModifierPosition) : baseClassName);
      if (!classGroupId) {
        if (!hasPostfixModifier) {
          result = originalClassName + (result.length > 0 ? " " + result : result);
          continue;
        }
        classGroupId = getClassGroupId(baseClassName);
        if (!classGroupId) {
          result = originalClassName + (result.length > 0 ? " " + result : result);
          continue;
        }
        hasPostfixModifier = false;
      }
      const variantModifier = sortModifiers(modifiers).join(":");
      const modifierId = hasImportantModifier ? variantModifier + IMPORTANT_MODIFIER : variantModifier;
      const classId = modifierId + classGroupId;
      if (classGroupsInConflict.includes(classId)) {
        continue;
      }
      classGroupsInConflict.push(classId);
      const conflictGroups = getConflictingClassGroupIds(classGroupId, hasPostfixModifier);
      for (let i = 0; i < conflictGroups.length; ++i) {
        const group = conflictGroups[i];
        classGroupsInConflict.push(modifierId + group);
      }
      result = originalClassName + (result.length > 0 ? " " + result : result);
    }
    return result;
  };
  function twJoin() {
    let index = 0;
    let argument;
    let resolvedValue;
    let string = "";
    while (index < arguments.length) {
      if (argument = arguments[index++]) {
        if (resolvedValue = toValue(argument)) {
          string && (string += " ");
          string += resolvedValue;
        }
      }
    }
    return string;
  }
  var toValue = (mix) => {
    if (typeof mix === "string") {
      return mix;
    }
    let resolvedValue;
    let string = "";
    for (let k = 0; k < mix.length; k++) {
      if (mix[k]) {
        if (resolvedValue = toValue(mix[k])) {
          string && (string += " ");
          string += resolvedValue;
        }
      }
    }
    return string;
  };
  function createTailwindMerge(createConfigFirst, ...createConfigRest) {
    let configUtils;
    let cacheGet;
    let cacheSet;
    let functionToCall = initTailwindMerge;
    function initTailwindMerge(classList) {
      const config = createConfigRest.reduce((previousConfig, createConfigCurrent) => createConfigCurrent(previousConfig), createConfigFirst());
      configUtils = createConfigUtils(config);
      cacheGet = configUtils.cache.get;
      cacheSet = configUtils.cache.set;
      functionToCall = tailwindMerge;
      return tailwindMerge(classList);
    }
    function tailwindMerge(classList) {
      const cachedResult = cacheGet(classList);
      if (cachedResult) {
        return cachedResult;
      }
      const result = mergeClassList(classList, configUtils);
      cacheSet(classList, result);
      return result;
    }
    return function callTailwindMerge() {
      return functionToCall(twJoin.apply(null, arguments));
    };
  }
  var fromTheme = (key) => {
    const themeGetter = (theme) => theme[key] || [];
    themeGetter.isThemeGetter = true;
    return themeGetter;
  };
  var arbitraryValueRegex = /^\[(?:([a-z-]+):)?(.+)\]$/i;
  var fractionRegex = /^\d+\/\d+$/;
  var stringLengths = /* @__PURE__ */ new Set(["px", "full", "screen"]);
  var tshirtUnitRegex = /^(\d+(\.\d+)?)?(xs|sm|md|lg|xl)$/;
  var lengthUnitRegex = /\d+(%|px|r?em|[sdl]?v([hwib]|min|max)|pt|pc|in|cm|mm|cap|ch|ex|r?lh|cq(w|h|i|b|min|max))|\b(calc|min|max|clamp)\(.+\)|^0$/;
  var colorFunctionRegex = /^(rgba?|hsla?|hwb|(ok)?(lab|lch)|color-mix)\(.+\)$/;
  var shadowRegex = /^(inset_)?-?((\d+)?\.?(\d+)[a-z]+|0)_-?((\d+)?\.?(\d+)[a-z]+|0)/;
  var imageRegex = /^(url|image|image-set|cross-fade|element|(repeating-)?(linear|radial|conic)-gradient)\(.+\)$/;
  var isLength = (value) => isNumber(value) || stringLengths.has(value) || fractionRegex.test(value);
  var isArbitraryLength = (value) => getIsArbitraryValue(value, "length", isLengthOnly);
  var isNumber = (value) => Boolean(value) && !Number.isNaN(Number(value));
  var isArbitraryNumber = (value) => getIsArbitraryValue(value, "number", isNumber);
  var isInteger = (value) => Boolean(value) && Number.isInteger(Number(value));
  var isPercent = (value) => value.endsWith("%") && isNumber(value.slice(0, -1));
  var isArbitraryValue = (value) => arbitraryValueRegex.test(value);
  var isTshirtSize = (value) => tshirtUnitRegex.test(value);
  var sizeLabels = /* @__PURE__ */ new Set(["length", "size", "percentage"]);
  var isArbitrarySize = (value) => getIsArbitraryValue(value, sizeLabels, isNever);
  var isArbitraryPosition = (value) => getIsArbitraryValue(value, "position", isNever);
  var imageLabels = /* @__PURE__ */ new Set(["image", "url"]);
  var isArbitraryImage = (value) => getIsArbitraryValue(value, imageLabels, isImage);
  var isArbitraryShadow = (value) => getIsArbitraryValue(value, "", isShadow);
  var isAny = () => true;
  var getIsArbitraryValue = (value, label, testValue) => {
    const result = arbitraryValueRegex.exec(value);
    if (result) {
      if (result[1]) {
        return typeof label === "string" ? result[1] === label : label.has(result[1]);
      }
      return testValue(result[2]);
    }
    return false;
  };
  var isLengthOnly = (value) => (
    // `colorFunctionRegex` check is necessary because color functions can have percentages in them which which would be incorrectly classified as lengths.
    // For example, `hsl(0 0% 0%)` would be classified as a length without this check.
    // I could also use lookbehind assertion in `lengthUnitRegex` but that isn't supported widely enough.
    lengthUnitRegex.test(value) && !colorFunctionRegex.test(value)
  );
  var isNever = () => false;
  var isShadow = (value) => shadowRegex.test(value);
  var isImage = (value) => imageRegex.test(value);
  var getDefaultConfig = () => {
    const colors = fromTheme("colors");
    const spacing = fromTheme("spacing");
    const blur = fromTheme("blur");
    const brightness = fromTheme("brightness");
    const borderColor = fromTheme("borderColor");
    const borderRadius = fromTheme("borderRadius");
    const borderSpacing = fromTheme("borderSpacing");
    const borderWidth = fromTheme("borderWidth");
    const contrast = fromTheme("contrast");
    const grayscale = fromTheme("grayscale");
    const hueRotate = fromTheme("hueRotate");
    const invert = fromTheme("invert");
    const gap = fromTheme("gap");
    const gradientColorStops = fromTheme("gradientColorStops");
    const gradientColorStopPositions = fromTheme("gradientColorStopPositions");
    const inset = fromTheme("inset");
    const margin = fromTheme("margin");
    const opacity = fromTheme("opacity");
    const padding = fromTheme("padding");
    const saturate = fromTheme("saturate");
    const scale = fromTheme("scale");
    const sepia = fromTheme("sepia");
    const skew = fromTheme("skew");
    const space = fromTheme("space");
    const translate = fromTheme("translate");
    const getOverscroll = () => ["auto", "contain", "none"];
    const getOverflow = () => ["auto", "hidden", "clip", "visible", "scroll"];
    const getSpacingWithAutoAndArbitrary = () => ["auto", isArbitraryValue, spacing];
    const getSpacingWithArbitrary = () => [isArbitraryValue, spacing];
    const getLengthWithEmptyAndArbitrary = () => ["", isLength, isArbitraryLength];
    const getNumberWithAutoAndArbitrary = () => ["auto", isNumber, isArbitraryValue];
    const getPositions = () => ["bottom", "center", "left", "left-bottom", "left-top", "right", "right-bottom", "right-top", "top"];
    const getLineStyles = () => ["solid", "dashed", "dotted", "double", "none"];
    const getBlendModes = () => ["normal", "multiply", "screen", "overlay", "darken", "lighten", "color-dodge", "color-burn", "hard-light", "soft-light", "difference", "exclusion", "hue", "saturation", "color", "luminosity"];
    const getAlign = () => ["start", "end", "center", "between", "around", "evenly", "stretch"];
    const getZeroAndEmpty = () => ["", "0", isArbitraryValue];
    const getBreaks = () => ["auto", "avoid", "all", "avoid-page", "page", "left", "right", "column"];
    const getNumberAndArbitrary = () => [isNumber, isArbitraryValue];
    return {
      cacheSize: 500,
      separator: ":",
      theme: {
        colors: [isAny],
        spacing: [isLength, isArbitraryLength],
        blur: ["none", "", isTshirtSize, isArbitraryValue],
        brightness: getNumberAndArbitrary(),
        borderColor: [colors],
        borderRadius: ["none", "", "full", isTshirtSize, isArbitraryValue],
        borderSpacing: getSpacingWithArbitrary(),
        borderWidth: getLengthWithEmptyAndArbitrary(),
        contrast: getNumberAndArbitrary(),
        grayscale: getZeroAndEmpty(),
        hueRotate: getNumberAndArbitrary(),
        invert: getZeroAndEmpty(),
        gap: getSpacingWithArbitrary(),
        gradientColorStops: [colors],
        gradientColorStopPositions: [isPercent, isArbitraryLength],
        inset: getSpacingWithAutoAndArbitrary(),
        margin: getSpacingWithAutoAndArbitrary(),
        opacity: getNumberAndArbitrary(),
        padding: getSpacingWithArbitrary(),
        saturate: getNumberAndArbitrary(),
        scale: getNumberAndArbitrary(),
        sepia: getZeroAndEmpty(),
        skew: getNumberAndArbitrary(),
        space: getSpacingWithArbitrary(),
        translate: getSpacingWithArbitrary()
      },
      classGroups: {
        // Layout
        /**
         * Aspect Ratio
         * @see https://tailwindcss.com/docs/aspect-ratio
         */
        aspect: [{
          aspect: ["auto", "square", "video", isArbitraryValue]
        }],
        /**
         * Container
         * @see https://tailwindcss.com/docs/container
         */
        container: ["container"],
        /**
         * Columns
         * @see https://tailwindcss.com/docs/columns
         */
        columns: [{
          columns: [isTshirtSize]
        }],
        /**
         * Break After
         * @see https://tailwindcss.com/docs/break-after
         */
        "break-after": [{
          "break-after": getBreaks()
        }],
        /**
         * Break Before
         * @see https://tailwindcss.com/docs/break-before
         */
        "break-before": [{
          "break-before": getBreaks()
        }],
        /**
         * Break Inside
         * @see https://tailwindcss.com/docs/break-inside
         */
        "break-inside": [{
          "break-inside": ["auto", "avoid", "avoid-page", "avoid-column"]
        }],
        /**
         * Box Decoration Break
         * @see https://tailwindcss.com/docs/box-decoration-break
         */
        "box-decoration": [{
          "box-decoration": ["slice", "clone"]
        }],
        /**
         * Box Sizing
         * @see https://tailwindcss.com/docs/box-sizing
         */
        box: [{
          box: ["border", "content"]
        }],
        /**
         * Display
         * @see https://tailwindcss.com/docs/display
         */
        display: ["block", "inline-block", "inline", "flex", "inline-flex", "table", "inline-table", "table-caption", "table-cell", "table-column", "table-column-group", "table-footer-group", "table-header-group", "table-row-group", "table-row", "flow-root", "grid", "inline-grid", "contents", "list-item", "hidden"],
        /**
         * Floats
         * @see https://tailwindcss.com/docs/float
         */
        float: [{
          float: ["right", "left", "none", "start", "end"]
        }],
        /**
         * Clear
         * @see https://tailwindcss.com/docs/clear
         */
        clear: [{
          clear: ["left", "right", "both", "none", "start", "end"]
        }],
        /**
         * Isolation
         * @see https://tailwindcss.com/docs/isolation
         */
        isolation: ["isolate", "isolation-auto"],
        /**
         * Object Fit
         * @see https://tailwindcss.com/docs/object-fit
         */
        "object-fit": [{
          object: ["contain", "cover", "fill", "none", "scale-down"]
        }],
        /**
         * Object Position
         * @see https://tailwindcss.com/docs/object-position
         */
        "object-position": [{
          object: [...getPositions(), isArbitraryValue]
        }],
        /**
         * Overflow
         * @see https://tailwindcss.com/docs/overflow
         */
        overflow: [{
          overflow: getOverflow()
        }],
        /**
         * Overflow X
         * @see https://tailwindcss.com/docs/overflow
         */
        "overflow-x": [{
          "overflow-x": getOverflow()
        }],
        /**
         * Overflow Y
         * @see https://tailwindcss.com/docs/overflow
         */
        "overflow-y": [{
          "overflow-y": getOverflow()
        }],
        /**
         * Overscroll Behavior
         * @see https://tailwindcss.com/docs/overscroll-behavior
         */
        overscroll: [{
          overscroll: getOverscroll()
        }],
        /**
         * Overscroll Behavior X
         * @see https://tailwindcss.com/docs/overscroll-behavior
         */
        "overscroll-x": [{
          "overscroll-x": getOverscroll()
        }],
        /**
         * Overscroll Behavior Y
         * @see https://tailwindcss.com/docs/overscroll-behavior
         */
        "overscroll-y": [{
          "overscroll-y": getOverscroll()
        }],
        /**
         * Position
         * @see https://tailwindcss.com/docs/position
         */
        position: ["static", "fixed", "absolute", "relative", "sticky"],
        /**
         * Top / Right / Bottom / Left
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        inset: [{
          inset: [inset]
        }],
        /**
         * Right / Left
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        "inset-x": [{
          "inset-x": [inset]
        }],
        /**
         * Top / Bottom
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        "inset-y": [{
          "inset-y": [inset]
        }],
        /**
         * Start
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        start: [{
          start: [inset]
        }],
        /**
         * End
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        end: [{
          end: [inset]
        }],
        /**
         * Top
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        top: [{
          top: [inset]
        }],
        /**
         * Right
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        right: [{
          right: [inset]
        }],
        /**
         * Bottom
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        bottom: [{
          bottom: [inset]
        }],
        /**
         * Left
         * @see https://tailwindcss.com/docs/top-right-bottom-left
         */
        left: [{
          left: [inset]
        }],
        /**
         * Visibility
         * @see https://tailwindcss.com/docs/visibility
         */
        visibility: ["visible", "invisible", "collapse"],
        /**
         * Z-Index
         * @see https://tailwindcss.com/docs/z-index
         */
        z: [{
          z: ["auto", isInteger, isArbitraryValue]
        }],
        // Flexbox and Grid
        /**
         * Flex Basis
         * @see https://tailwindcss.com/docs/flex-basis
         */
        basis: [{
          basis: getSpacingWithAutoAndArbitrary()
        }],
        /**
         * Flex Direction
         * @see https://tailwindcss.com/docs/flex-direction
         */
        "flex-direction": [{
          flex: ["row", "row-reverse", "col", "col-reverse"]
        }],
        /**
         * Flex Wrap
         * @see https://tailwindcss.com/docs/flex-wrap
         */
        "flex-wrap": [{
          flex: ["wrap", "wrap-reverse", "nowrap"]
        }],
        /**
         * Flex
         * @see https://tailwindcss.com/docs/flex
         */
        flex: [{
          flex: ["1", "auto", "initial", "none", isArbitraryValue]
        }],
        /**
         * Flex Grow
         * @see https://tailwindcss.com/docs/flex-grow
         */
        grow: [{
          grow: getZeroAndEmpty()
        }],
        /**
         * Flex Shrink
         * @see https://tailwindcss.com/docs/flex-shrink
         */
        shrink: [{
          shrink: getZeroAndEmpty()
        }],
        /**
         * Order
         * @see https://tailwindcss.com/docs/order
         */
        order: [{
          order: ["first", "last", "none", isInteger, isArbitraryValue]
        }],
        /**
         * Grid Template Columns
         * @see https://tailwindcss.com/docs/grid-template-columns
         */
        "grid-cols": [{
          "grid-cols": [isAny]
        }],
        /**
         * Grid Column Start / End
         * @see https://tailwindcss.com/docs/grid-column
         */
        "col-start-end": [{
          col: ["auto", {
            span: ["full", isInteger, isArbitraryValue]
          }, isArbitraryValue]
        }],
        /**
         * Grid Column Start
         * @see https://tailwindcss.com/docs/grid-column
         */
        "col-start": [{
          "col-start": getNumberWithAutoAndArbitrary()
        }],
        /**
         * Grid Column End
         * @see https://tailwindcss.com/docs/grid-column
         */
        "col-end": [{
          "col-end": getNumberWithAutoAndArbitrary()
        }],
        /**
         * Grid Template Rows
         * @see https://tailwindcss.com/docs/grid-template-rows
         */
        "grid-rows": [{
          "grid-rows": [isAny]
        }],
        /**
         * Grid Row Start / End
         * @see https://tailwindcss.com/docs/grid-row
         */
        "row-start-end": [{
          row: ["auto", {
            span: [isInteger, isArbitraryValue]
          }, isArbitraryValue]
        }],
        /**
         * Grid Row Start
         * @see https://tailwindcss.com/docs/grid-row
         */
        "row-start": [{
          "row-start": getNumberWithAutoAndArbitrary()
        }],
        /**
         * Grid Row End
         * @see https://tailwindcss.com/docs/grid-row
         */
        "row-end": [{
          "row-end": getNumberWithAutoAndArbitrary()
        }],
        /**
         * Grid Auto Flow
         * @see https://tailwindcss.com/docs/grid-auto-flow
         */
        "grid-flow": [{
          "grid-flow": ["row", "col", "dense", "row-dense", "col-dense"]
        }],
        /**
         * Grid Auto Columns
         * @see https://tailwindcss.com/docs/grid-auto-columns
         */
        "auto-cols": [{
          "auto-cols": ["auto", "min", "max", "fr", isArbitraryValue]
        }],
        /**
         * Grid Auto Rows
         * @see https://tailwindcss.com/docs/grid-auto-rows
         */
        "auto-rows": [{
          "auto-rows": ["auto", "min", "max", "fr", isArbitraryValue]
        }],
        /**
         * Gap
         * @see https://tailwindcss.com/docs/gap
         */
        gap: [{
          gap: [gap]
        }],
        /**
         * Gap X
         * @see https://tailwindcss.com/docs/gap
         */
        "gap-x": [{
          "gap-x": [gap]
        }],
        /**
         * Gap Y
         * @see https://tailwindcss.com/docs/gap
         */
        "gap-y": [{
          "gap-y": [gap]
        }],
        /**
         * Justify Content
         * @see https://tailwindcss.com/docs/justify-content
         */
        "justify-content": [{
          justify: ["normal", ...getAlign()]
        }],
        /**
         * Justify Items
         * @see https://tailwindcss.com/docs/justify-items
         */
        "justify-items": [{
          "justify-items": ["start", "end", "center", "stretch"]
        }],
        /**
         * Justify Self
         * @see https://tailwindcss.com/docs/justify-self
         */
        "justify-self": [{
          "justify-self": ["auto", "start", "end", "center", "stretch"]
        }],
        /**
         * Align Content
         * @see https://tailwindcss.com/docs/align-content
         */
        "align-content": [{
          content: ["normal", ...getAlign(), "baseline"]
        }],
        /**
         * Align Items
         * @see https://tailwindcss.com/docs/align-items
         */
        "align-items": [{
          items: ["start", "end", "center", "baseline", "stretch"]
        }],
        /**
         * Align Self
         * @see https://tailwindcss.com/docs/align-self
         */
        "align-self": [{
          self: ["auto", "start", "end", "center", "stretch", "baseline"]
        }],
        /**
         * Place Content
         * @see https://tailwindcss.com/docs/place-content
         */
        "place-content": [{
          "place-content": [...getAlign(), "baseline"]
        }],
        /**
         * Place Items
         * @see https://tailwindcss.com/docs/place-items
         */
        "place-items": [{
          "place-items": ["start", "end", "center", "baseline", "stretch"]
        }],
        /**
         * Place Self
         * @see https://tailwindcss.com/docs/place-self
         */
        "place-self": [{
          "place-self": ["auto", "start", "end", "center", "stretch"]
        }],
        // Spacing
        /**
         * Padding
         * @see https://tailwindcss.com/docs/padding
         */
        p: [{
          p: [padding]
        }],
        /**
         * Padding X
         * @see https://tailwindcss.com/docs/padding
         */
        px: [{
          px: [padding]
        }],
        /**
         * Padding Y
         * @see https://tailwindcss.com/docs/padding
         */
        py: [{
          py: [padding]
        }],
        /**
         * Padding Start
         * @see https://tailwindcss.com/docs/padding
         */
        ps: [{
          ps: [padding]
        }],
        /**
         * Padding End
         * @see https://tailwindcss.com/docs/padding
         */
        pe: [{
          pe: [padding]
        }],
        /**
         * Padding Top
         * @see https://tailwindcss.com/docs/padding
         */
        pt: [{
          pt: [padding]
        }],
        /**
         * Padding Right
         * @see https://tailwindcss.com/docs/padding
         */
        pr: [{
          pr: [padding]
        }],
        /**
         * Padding Bottom
         * @see https://tailwindcss.com/docs/padding
         */
        pb: [{
          pb: [padding]
        }],
        /**
         * Padding Left
         * @see https://tailwindcss.com/docs/padding
         */
        pl: [{
          pl: [padding]
        }],
        /**
         * Margin
         * @see https://tailwindcss.com/docs/margin
         */
        m: [{
          m: [margin]
        }],
        /**
         * Margin X
         * @see https://tailwindcss.com/docs/margin
         */
        mx: [{
          mx: [margin]
        }],
        /**
         * Margin Y
         * @see https://tailwindcss.com/docs/margin
         */
        my: [{
          my: [margin]
        }],
        /**
         * Margin Start
         * @see https://tailwindcss.com/docs/margin
         */
        ms: [{
          ms: [margin]
        }],
        /**
         * Margin End
         * @see https://tailwindcss.com/docs/margin
         */
        me: [{
          me: [margin]
        }],
        /**
         * Margin Top
         * @see https://tailwindcss.com/docs/margin
         */
        mt: [{
          mt: [margin]
        }],
        /**
         * Margin Right
         * @see https://tailwindcss.com/docs/margin
         */
        mr: [{
          mr: [margin]
        }],
        /**
         * Margin Bottom
         * @see https://tailwindcss.com/docs/margin
         */
        mb: [{
          mb: [margin]
        }],
        /**
         * Margin Left
         * @see https://tailwindcss.com/docs/margin
         */
        ml: [{
          ml: [margin]
        }],
        /**
         * Space Between X
         * @see https://tailwindcss.com/docs/space
         */
        "space-x": [{
          "space-x": [space]
        }],
        /**
         * Space Between X Reverse
         * @see https://tailwindcss.com/docs/space
         */
        "space-x-reverse": ["space-x-reverse"],
        /**
         * Space Between Y
         * @see https://tailwindcss.com/docs/space
         */
        "space-y": [{
          "space-y": [space]
        }],
        /**
         * Space Between Y Reverse
         * @see https://tailwindcss.com/docs/space
         */
        "space-y-reverse": ["space-y-reverse"],
        // Sizing
        /**
         * Width
         * @see https://tailwindcss.com/docs/width
         */
        w: [{
          w: ["auto", "min", "max", "fit", "svw", "lvw", "dvw", isArbitraryValue, spacing]
        }],
        /**
         * Min-Width
         * @see https://tailwindcss.com/docs/min-width
         */
        "min-w": [{
          "min-w": [isArbitraryValue, spacing, "min", "max", "fit"]
        }],
        /**
         * Max-Width
         * @see https://tailwindcss.com/docs/max-width
         */
        "max-w": [{
          "max-w": [isArbitraryValue, spacing, "none", "full", "min", "max", "fit", "prose", {
            screen: [isTshirtSize]
          }, isTshirtSize]
        }],
        /**
         * Height
         * @see https://tailwindcss.com/docs/height
         */
        h: [{
          h: [isArbitraryValue, spacing, "auto", "min", "max", "fit", "svh", "lvh", "dvh"]
        }],
        /**
         * Min-Height
         * @see https://tailwindcss.com/docs/min-height
         */
        "min-h": [{
          "min-h": [isArbitraryValue, spacing, "min", "max", "fit", "svh", "lvh", "dvh"]
        }],
        /**
         * Max-Height
         * @see https://tailwindcss.com/docs/max-height
         */
        "max-h": [{
          "max-h": [isArbitraryValue, spacing, "min", "max", "fit", "svh", "lvh", "dvh"]
        }],
        /**
         * Size
         * @see https://tailwindcss.com/docs/size
         */
        size: [{
          size: [isArbitraryValue, spacing, "auto", "min", "max", "fit"]
        }],
        // Typography
        /**
         * Font Size
         * @see https://tailwindcss.com/docs/font-size
         */
        "font-size": [{
          text: ["base", isTshirtSize, isArbitraryLength]
        }],
        /**
         * Font Smoothing
         * @see https://tailwindcss.com/docs/font-smoothing
         */
        "font-smoothing": ["antialiased", "subpixel-antialiased"],
        /**
         * Font Style
         * @see https://tailwindcss.com/docs/font-style
         */
        "font-style": ["italic", "not-italic"],
        /**
         * Font Weight
         * @see https://tailwindcss.com/docs/font-weight
         */
        "font-weight": [{
          font: ["thin", "extralight", "light", "normal", "medium", "semibold", "bold", "extrabold", "black", isArbitraryNumber]
        }],
        /**
         * Font Family
         * @see https://tailwindcss.com/docs/font-family
         */
        "font-family": [{
          font: [isAny]
        }],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-normal": ["normal-nums"],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-ordinal": ["ordinal"],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-slashed-zero": ["slashed-zero"],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-figure": ["lining-nums", "oldstyle-nums"],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-spacing": ["proportional-nums", "tabular-nums"],
        /**
         * Font Variant Numeric
         * @see https://tailwindcss.com/docs/font-variant-numeric
         */
        "fvn-fraction": ["diagonal-fractions", "stacked-fractions"],
        /**
         * Letter Spacing
         * @see https://tailwindcss.com/docs/letter-spacing
         */
        tracking: [{
          tracking: ["tighter", "tight", "normal", "wide", "wider", "widest", isArbitraryValue]
        }],
        /**
         * Line Clamp
         * @see https://tailwindcss.com/docs/line-clamp
         */
        "line-clamp": [{
          "line-clamp": ["none", isNumber, isArbitraryNumber]
        }],
        /**
         * Line Height
         * @see https://tailwindcss.com/docs/line-height
         */
        leading: [{
          leading: ["none", "tight", "snug", "normal", "relaxed", "loose", isLength, isArbitraryValue]
        }],
        /**
         * List Style Image
         * @see https://tailwindcss.com/docs/list-style-image
         */
        "list-image": [{
          "list-image": ["none", isArbitraryValue]
        }],
        /**
         * List Style Type
         * @see https://tailwindcss.com/docs/list-style-type
         */
        "list-style-type": [{
          list: ["none", "disc", "decimal", isArbitraryValue]
        }],
        /**
         * List Style Position
         * @see https://tailwindcss.com/docs/list-style-position
         */
        "list-style-position": [{
          list: ["inside", "outside"]
        }],
        /**
         * Placeholder Color
         * @deprecated since Tailwind CSS v3.0.0
         * @see https://tailwindcss.com/docs/placeholder-color
         */
        "placeholder-color": [{
          placeholder: [colors]
        }],
        /**
         * Placeholder Opacity
         * @see https://tailwindcss.com/docs/placeholder-opacity
         */
        "placeholder-opacity": [{
          "placeholder-opacity": [opacity]
        }],
        /**
         * Text Alignment
         * @see https://tailwindcss.com/docs/text-align
         */
        "text-alignment": [{
          text: ["left", "center", "right", "justify", "start", "end"]
        }],
        /**
         * Text Color
         * @see https://tailwindcss.com/docs/text-color
         */
        "text-color": [{
          text: [colors]
        }],
        /**
         * Text Opacity
         * @see https://tailwindcss.com/docs/text-opacity
         */
        "text-opacity": [{
          "text-opacity": [opacity]
        }],
        /**
         * Text Decoration
         * @see https://tailwindcss.com/docs/text-decoration
         */
        "text-decoration": ["underline", "overline", "line-through", "no-underline"],
        /**
         * Text Decoration Style
         * @see https://tailwindcss.com/docs/text-decoration-style
         */
        "text-decoration-style": [{
          decoration: [...getLineStyles(), "wavy"]
        }],
        /**
         * Text Decoration Thickness
         * @see https://tailwindcss.com/docs/text-decoration-thickness
         */
        "text-decoration-thickness": [{
          decoration: ["auto", "from-font", isLength, isArbitraryLength]
        }],
        /**
         * Text Underline Offset
         * @see https://tailwindcss.com/docs/text-underline-offset
         */
        "underline-offset": [{
          "underline-offset": ["auto", isLength, isArbitraryValue]
        }],
        /**
         * Text Decoration Color
         * @see https://tailwindcss.com/docs/text-decoration-color
         */
        "text-decoration-color": [{
          decoration: [colors]
        }],
        /**
         * Text Transform
         * @see https://tailwindcss.com/docs/text-transform
         */
        "text-transform": ["uppercase", "lowercase", "capitalize", "normal-case"],
        /**
         * Text Overflow
         * @see https://tailwindcss.com/docs/text-overflow
         */
        "text-overflow": ["truncate", "text-ellipsis", "text-clip"],
        /**
         * Text Wrap
         * @see https://tailwindcss.com/docs/text-wrap
         */
        "text-wrap": [{
          text: ["wrap", "nowrap", "balance", "pretty"]
        }],
        /**
         * Text Indent
         * @see https://tailwindcss.com/docs/text-indent
         */
        indent: [{
          indent: getSpacingWithArbitrary()
        }],
        /**
         * Vertical Alignment
         * @see https://tailwindcss.com/docs/vertical-align
         */
        "vertical-align": [{
          align: ["baseline", "top", "middle", "bottom", "text-top", "text-bottom", "sub", "super", isArbitraryValue]
        }],
        /**
         * Whitespace
         * @see https://tailwindcss.com/docs/whitespace
         */
        whitespace: [{
          whitespace: ["normal", "nowrap", "pre", "pre-line", "pre-wrap", "break-spaces"]
        }],
        /**
         * Word Break
         * @see https://tailwindcss.com/docs/word-break
         */
        break: [{
          break: ["normal", "words", "all", "keep"]
        }],
        /**
         * Hyphens
         * @see https://tailwindcss.com/docs/hyphens
         */
        hyphens: [{
          hyphens: ["none", "manual", "auto"]
        }],
        /**
         * Content
         * @see https://tailwindcss.com/docs/content
         */
        content: [{
          content: ["none", isArbitraryValue]
        }],
        // Backgrounds
        /**
         * Background Attachment
         * @see https://tailwindcss.com/docs/background-attachment
         */
        "bg-attachment": [{
          bg: ["fixed", "local", "scroll"]
        }],
        /**
         * Background Clip
         * @see https://tailwindcss.com/docs/background-clip
         */
        "bg-clip": [{
          "bg-clip": ["border", "padding", "content", "text"]
        }],
        /**
         * Background Opacity
         * @deprecated since Tailwind CSS v3.0.0
         * @see https://tailwindcss.com/docs/background-opacity
         */
        "bg-opacity": [{
          "bg-opacity": [opacity]
        }],
        /**
         * Background Origin
         * @see https://tailwindcss.com/docs/background-origin
         */
        "bg-origin": [{
          "bg-origin": ["border", "padding", "content"]
        }],
        /**
         * Background Position
         * @see https://tailwindcss.com/docs/background-position
         */
        "bg-position": [{
          bg: [...getPositions(), isArbitraryPosition]
        }],
        /**
         * Background Repeat
         * @see https://tailwindcss.com/docs/background-repeat
         */
        "bg-repeat": [{
          bg: ["no-repeat", {
            repeat: ["", "x", "y", "round", "space"]
          }]
        }],
        /**
         * Background Size
         * @see https://tailwindcss.com/docs/background-size
         */
        "bg-size": [{
          bg: ["auto", "cover", "contain", isArbitrarySize]
        }],
        /**
         * Background Image
         * @see https://tailwindcss.com/docs/background-image
         */
        "bg-image": [{
          bg: ["none", {
            "gradient-to": ["t", "tr", "r", "br", "b", "bl", "l", "tl"]
          }, isArbitraryImage]
        }],
        /**
         * Background Color
         * @see https://tailwindcss.com/docs/background-color
         */
        "bg-color": [{
          bg: [colors]
        }],
        /**
         * Gradient Color Stops From Position
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-from-pos": [{
          from: [gradientColorStopPositions]
        }],
        /**
         * Gradient Color Stops Via Position
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-via-pos": [{
          via: [gradientColorStopPositions]
        }],
        /**
         * Gradient Color Stops To Position
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-to-pos": [{
          to: [gradientColorStopPositions]
        }],
        /**
         * Gradient Color Stops From
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-from": [{
          from: [gradientColorStops]
        }],
        /**
         * Gradient Color Stops Via
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-via": [{
          via: [gradientColorStops]
        }],
        /**
         * Gradient Color Stops To
         * @see https://tailwindcss.com/docs/gradient-color-stops
         */
        "gradient-to": [{
          to: [gradientColorStops]
        }],
        // Borders
        /**
         * Border Radius
         * @see https://tailwindcss.com/docs/border-radius
         */
        rounded: [{
          rounded: [borderRadius]
        }],
        /**
         * Border Radius Start
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-s": [{
          "rounded-s": [borderRadius]
        }],
        /**
         * Border Radius End
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-e": [{
          "rounded-e": [borderRadius]
        }],
        /**
         * Border Radius Top
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-t": [{
          "rounded-t": [borderRadius]
        }],
        /**
         * Border Radius Right
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-r": [{
          "rounded-r": [borderRadius]
        }],
        /**
         * Border Radius Bottom
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-b": [{
          "rounded-b": [borderRadius]
        }],
        /**
         * Border Radius Left
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-l": [{
          "rounded-l": [borderRadius]
        }],
        /**
         * Border Radius Start Start
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-ss": [{
          "rounded-ss": [borderRadius]
        }],
        /**
         * Border Radius Start End
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-se": [{
          "rounded-se": [borderRadius]
        }],
        /**
         * Border Radius End End
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-ee": [{
          "rounded-ee": [borderRadius]
        }],
        /**
         * Border Radius End Start
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-es": [{
          "rounded-es": [borderRadius]
        }],
        /**
         * Border Radius Top Left
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-tl": [{
          "rounded-tl": [borderRadius]
        }],
        /**
         * Border Radius Top Right
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-tr": [{
          "rounded-tr": [borderRadius]
        }],
        /**
         * Border Radius Bottom Right
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-br": [{
          "rounded-br": [borderRadius]
        }],
        /**
         * Border Radius Bottom Left
         * @see https://tailwindcss.com/docs/border-radius
         */
        "rounded-bl": [{
          "rounded-bl": [borderRadius]
        }],
        /**
         * Border Width
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w": [{
          border: [borderWidth]
        }],
        /**
         * Border Width X
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-x": [{
          "border-x": [borderWidth]
        }],
        /**
         * Border Width Y
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-y": [{
          "border-y": [borderWidth]
        }],
        /**
         * Border Width Start
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-s": [{
          "border-s": [borderWidth]
        }],
        /**
         * Border Width End
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-e": [{
          "border-e": [borderWidth]
        }],
        /**
         * Border Width Top
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-t": [{
          "border-t": [borderWidth]
        }],
        /**
         * Border Width Right
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-r": [{
          "border-r": [borderWidth]
        }],
        /**
         * Border Width Bottom
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-b": [{
          "border-b": [borderWidth]
        }],
        /**
         * Border Width Left
         * @see https://tailwindcss.com/docs/border-width
         */
        "border-w-l": [{
          "border-l": [borderWidth]
        }],
        /**
         * Border Opacity
         * @see https://tailwindcss.com/docs/border-opacity
         */
        "border-opacity": [{
          "border-opacity": [opacity]
        }],
        /**
         * Border Style
         * @see https://tailwindcss.com/docs/border-style
         */
        "border-style": [{
          border: [...getLineStyles(), "hidden"]
        }],
        /**
         * Divide Width X
         * @see https://tailwindcss.com/docs/divide-width
         */
        "divide-x": [{
          "divide-x": [borderWidth]
        }],
        /**
         * Divide Width X Reverse
         * @see https://tailwindcss.com/docs/divide-width
         */
        "divide-x-reverse": ["divide-x-reverse"],
        /**
         * Divide Width Y
         * @see https://tailwindcss.com/docs/divide-width
         */
        "divide-y": [{
          "divide-y": [borderWidth]
        }],
        /**
         * Divide Width Y Reverse
         * @see https://tailwindcss.com/docs/divide-width
         */
        "divide-y-reverse": ["divide-y-reverse"],
        /**
         * Divide Opacity
         * @see https://tailwindcss.com/docs/divide-opacity
         */
        "divide-opacity": [{
          "divide-opacity": [opacity]
        }],
        /**
         * Divide Style
         * @see https://tailwindcss.com/docs/divide-style
         */
        "divide-style": [{
          divide: getLineStyles()
        }],
        /**
         * Border Color
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color": [{
          border: [borderColor]
        }],
        /**
         * Border Color X
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-x": [{
          "border-x": [borderColor]
        }],
        /**
         * Border Color Y
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-y": [{
          "border-y": [borderColor]
        }],
        /**
         * Border Color S
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-s": [{
          "border-s": [borderColor]
        }],
        /**
         * Border Color E
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-e": [{
          "border-e": [borderColor]
        }],
        /**
         * Border Color Top
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-t": [{
          "border-t": [borderColor]
        }],
        /**
         * Border Color Right
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-r": [{
          "border-r": [borderColor]
        }],
        /**
         * Border Color Bottom
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-b": [{
          "border-b": [borderColor]
        }],
        /**
         * Border Color Left
         * @see https://tailwindcss.com/docs/border-color
         */
        "border-color-l": [{
          "border-l": [borderColor]
        }],
        /**
         * Divide Color
         * @see https://tailwindcss.com/docs/divide-color
         */
        "divide-color": [{
          divide: [borderColor]
        }],
        /**
         * Outline Style
         * @see https://tailwindcss.com/docs/outline-style
         */
        "outline-style": [{
          outline: ["", ...getLineStyles()]
        }],
        /**
         * Outline Offset
         * @see https://tailwindcss.com/docs/outline-offset
         */
        "outline-offset": [{
          "outline-offset": [isLength, isArbitraryValue]
        }],
        /**
         * Outline Width
         * @see https://tailwindcss.com/docs/outline-width
         */
        "outline-w": [{
          outline: [isLength, isArbitraryLength]
        }],
        /**
         * Outline Color
         * @see https://tailwindcss.com/docs/outline-color
         */
        "outline-color": [{
          outline: [colors]
        }],
        /**
         * Ring Width
         * @see https://tailwindcss.com/docs/ring-width
         */
        "ring-w": [{
          ring: getLengthWithEmptyAndArbitrary()
        }],
        /**
         * Ring Width Inset
         * @see https://tailwindcss.com/docs/ring-width
         */
        "ring-w-inset": ["ring-inset"],
        /**
         * Ring Color
         * @see https://tailwindcss.com/docs/ring-color
         */
        "ring-color": [{
          ring: [colors]
        }],
        /**
         * Ring Opacity
         * @see https://tailwindcss.com/docs/ring-opacity
         */
        "ring-opacity": [{
          "ring-opacity": [opacity]
        }],
        /**
         * Ring Offset Width
         * @see https://tailwindcss.com/docs/ring-offset-width
         */
        "ring-offset-w": [{
          "ring-offset": [isLength, isArbitraryLength]
        }],
        /**
         * Ring Offset Color
         * @see https://tailwindcss.com/docs/ring-offset-color
         */
        "ring-offset-color": [{
          "ring-offset": [colors]
        }],
        // Effects
        /**
         * Box Shadow
         * @see https://tailwindcss.com/docs/box-shadow
         */
        shadow: [{
          shadow: ["", "inner", "none", isTshirtSize, isArbitraryShadow]
        }],
        /**
         * Box Shadow Color
         * @see https://tailwindcss.com/docs/box-shadow-color
         */
        "shadow-color": [{
          shadow: [isAny]
        }],
        /**
         * Opacity
         * @see https://tailwindcss.com/docs/opacity
         */
        opacity: [{
          opacity: [opacity]
        }],
        /**
         * Mix Blend Mode
         * @see https://tailwindcss.com/docs/mix-blend-mode
         */
        "mix-blend": [{
          "mix-blend": [...getBlendModes(), "plus-lighter", "plus-darker"]
        }],
        /**
         * Background Blend Mode
         * @see https://tailwindcss.com/docs/background-blend-mode
         */
        "bg-blend": [{
          "bg-blend": getBlendModes()
        }],
        // Filters
        /**
         * Filter
         * @deprecated since Tailwind CSS v3.0.0
         * @see https://tailwindcss.com/docs/filter
         */
        filter: [{
          filter: ["", "none"]
        }],
        /**
         * Blur
         * @see https://tailwindcss.com/docs/blur
         */
        blur: [{
          blur: [blur]
        }],
        /**
         * Brightness
         * @see https://tailwindcss.com/docs/brightness
         */
        brightness: [{
          brightness: [brightness]
        }],
        /**
         * Contrast
         * @see https://tailwindcss.com/docs/contrast
         */
        contrast: [{
          contrast: [contrast]
        }],
        /**
         * Drop Shadow
         * @see https://tailwindcss.com/docs/drop-shadow
         */
        "drop-shadow": [{
          "drop-shadow": ["", "none", isTshirtSize, isArbitraryValue]
        }],
        /**
         * Grayscale
         * @see https://tailwindcss.com/docs/grayscale
         */
        grayscale: [{
          grayscale: [grayscale]
        }],
        /**
         * Hue Rotate
         * @see https://tailwindcss.com/docs/hue-rotate
         */
        "hue-rotate": [{
          "hue-rotate": [hueRotate]
        }],
        /**
         * Invert
         * @see https://tailwindcss.com/docs/invert
         */
        invert: [{
          invert: [invert]
        }],
        /**
         * Saturate
         * @see https://tailwindcss.com/docs/saturate
         */
        saturate: [{
          saturate: [saturate]
        }],
        /**
         * Sepia
         * @see https://tailwindcss.com/docs/sepia
         */
        sepia: [{
          sepia: [sepia]
        }],
        /**
         * Backdrop Filter
         * @deprecated since Tailwind CSS v3.0.0
         * @see https://tailwindcss.com/docs/backdrop-filter
         */
        "backdrop-filter": [{
          "backdrop-filter": ["", "none"]
        }],
        /**
         * Backdrop Blur
         * @see https://tailwindcss.com/docs/backdrop-blur
         */
        "backdrop-blur": [{
          "backdrop-blur": [blur]
        }],
        /**
         * Backdrop Brightness
         * @see https://tailwindcss.com/docs/backdrop-brightness
         */
        "backdrop-brightness": [{
          "backdrop-brightness": [brightness]
        }],
        /**
         * Backdrop Contrast
         * @see https://tailwindcss.com/docs/backdrop-contrast
         */
        "backdrop-contrast": [{
          "backdrop-contrast": [contrast]
        }],
        /**
         * Backdrop Grayscale
         * @see https://tailwindcss.com/docs/backdrop-grayscale
         */
        "backdrop-grayscale": [{
          "backdrop-grayscale": [grayscale]
        }],
        /**
         * Backdrop Hue Rotate
         * @see https://tailwindcss.com/docs/backdrop-hue-rotate
         */
        "backdrop-hue-rotate": [{
          "backdrop-hue-rotate": [hueRotate]
        }],
        /**
         * Backdrop Invert
         * @see https://tailwindcss.com/docs/backdrop-invert
         */
        "backdrop-invert": [{
          "backdrop-invert": [invert]
        }],
        /**
         * Backdrop Opacity
         * @see https://tailwindcss.com/docs/backdrop-opacity
         */
        "backdrop-opacity": [{
          "backdrop-opacity": [opacity]
        }],
        /**
         * Backdrop Saturate
         * @see https://tailwindcss.com/docs/backdrop-saturate
         */
        "backdrop-saturate": [{
          "backdrop-saturate": [saturate]
        }],
        /**
         * Backdrop Sepia
         * @see https://tailwindcss.com/docs/backdrop-sepia
         */
        "backdrop-sepia": [{
          "backdrop-sepia": [sepia]
        }],
        // Tables
        /**
         * Border Collapse
         * @see https://tailwindcss.com/docs/border-collapse
         */
        "border-collapse": [{
          border: ["collapse", "separate"]
        }],
        /**
         * Border Spacing
         * @see https://tailwindcss.com/docs/border-spacing
         */
        "border-spacing": [{
          "border-spacing": [borderSpacing]
        }],
        /**
         * Border Spacing X
         * @see https://tailwindcss.com/docs/border-spacing
         */
        "border-spacing-x": [{
          "border-spacing-x": [borderSpacing]
        }],
        /**
         * Border Spacing Y
         * @see https://tailwindcss.com/docs/border-spacing
         */
        "border-spacing-y": [{
          "border-spacing-y": [borderSpacing]
        }],
        /**
         * Table Layout
         * @see https://tailwindcss.com/docs/table-layout
         */
        "table-layout": [{
          table: ["auto", "fixed"]
        }],
        /**
         * Caption Side
         * @see https://tailwindcss.com/docs/caption-side
         */
        caption: [{
          caption: ["top", "bottom"]
        }],
        // Transitions and Animation
        /**
         * Tranisition Property
         * @see https://tailwindcss.com/docs/transition-property
         */
        transition: [{
          transition: ["none", "all", "", "colors", "opacity", "shadow", "transform", isArbitraryValue]
        }],
        /**
         * Transition Duration
         * @see https://tailwindcss.com/docs/transition-duration
         */
        duration: [{
          duration: getNumberAndArbitrary()
        }],
        /**
         * Transition Timing Function
         * @see https://tailwindcss.com/docs/transition-timing-function
         */
        ease: [{
          ease: ["linear", "in", "out", "in-out", isArbitraryValue]
        }],
        /**
         * Transition Delay
         * @see https://tailwindcss.com/docs/transition-delay
         */
        delay: [{
          delay: getNumberAndArbitrary()
        }],
        /**
         * Animation
         * @see https://tailwindcss.com/docs/animation
         */
        animate: [{
          animate: ["none", "spin", "ping", "pulse", "bounce", isArbitraryValue]
        }],
        // Transforms
        /**
         * Transform
         * @see https://tailwindcss.com/docs/transform
         */
        transform: [{
          transform: ["", "gpu", "none"]
        }],
        /**
         * Scale
         * @see https://tailwindcss.com/docs/scale
         */
        scale: [{
          scale: [scale]
        }],
        /**
         * Scale X
         * @see https://tailwindcss.com/docs/scale
         */
        "scale-x": [{
          "scale-x": [scale]
        }],
        /**
         * Scale Y
         * @see https://tailwindcss.com/docs/scale
         */
        "scale-y": [{
          "scale-y": [scale]
        }],
        /**
         * Rotate
         * @see https://tailwindcss.com/docs/rotate
         */
        rotate: [{
          rotate: [isInteger, isArbitraryValue]
        }],
        /**
         * Translate X
         * @see https://tailwindcss.com/docs/translate
         */
        "translate-x": [{
          "translate-x": [translate]
        }],
        /**
         * Translate Y
         * @see https://tailwindcss.com/docs/translate
         */
        "translate-y": [{
          "translate-y": [translate]
        }],
        /**
         * Skew X
         * @see https://tailwindcss.com/docs/skew
         */
        "skew-x": [{
          "skew-x": [skew]
        }],
        /**
         * Skew Y
         * @see https://tailwindcss.com/docs/skew
         */
        "skew-y": [{
          "skew-y": [skew]
        }],
        /**
         * Transform Origin
         * @see https://tailwindcss.com/docs/transform-origin
         */
        "transform-origin": [{
          origin: ["center", "top", "top-right", "right", "bottom-right", "bottom", "bottom-left", "left", "top-left", isArbitraryValue]
        }],
        // Interactivity
        /**
         * Accent Color
         * @see https://tailwindcss.com/docs/accent-color
         */
        accent: [{
          accent: ["auto", colors]
        }],
        /**
         * Appearance
         * @see https://tailwindcss.com/docs/appearance
         */
        appearance: [{
          appearance: ["none", "auto"]
        }],
        /**
         * Cursor
         * @see https://tailwindcss.com/docs/cursor
         */
        cursor: [{
          cursor: ["auto", "default", "pointer", "wait", "text", "move", "help", "not-allowed", "none", "context-menu", "progress", "cell", "crosshair", "vertical-text", "alias", "copy", "no-drop", "grab", "grabbing", "all-scroll", "col-resize", "row-resize", "n-resize", "e-resize", "s-resize", "w-resize", "ne-resize", "nw-resize", "se-resize", "sw-resize", "ew-resize", "ns-resize", "nesw-resize", "nwse-resize", "zoom-in", "zoom-out", isArbitraryValue]
        }],
        /**
         * Caret Color
         * @see https://tailwindcss.com/docs/just-in-time-mode#caret-color-utilities
         */
        "caret-color": [{
          caret: [colors]
        }],
        /**
         * Pointer Events
         * @see https://tailwindcss.com/docs/pointer-events
         */
        "pointer-events": [{
          "pointer-events": ["none", "auto"]
        }],
        /**
         * Resize
         * @see https://tailwindcss.com/docs/resize
         */
        resize: [{
          resize: ["none", "y", "x", ""]
        }],
        /**
         * Scroll Behavior
         * @see https://tailwindcss.com/docs/scroll-behavior
         */
        "scroll-behavior": [{
          scroll: ["auto", "smooth"]
        }],
        /**
         * Scroll Margin
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-m": [{
          "scroll-m": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin X
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-mx": [{
          "scroll-mx": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Y
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-my": [{
          "scroll-my": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Start
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-ms": [{
          "scroll-ms": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin End
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-me": [{
          "scroll-me": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Top
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-mt": [{
          "scroll-mt": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Right
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-mr": [{
          "scroll-mr": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Bottom
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-mb": [{
          "scroll-mb": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Margin Left
         * @see https://tailwindcss.com/docs/scroll-margin
         */
        "scroll-ml": [{
          "scroll-ml": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-p": [{
          "scroll-p": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding X
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-px": [{
          "scroll-px": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Y
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-py": [{
          "scroll-py": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Start
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-ps": [{
          "scroll-ps": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding End
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-pe": [{
          "scroll-pe": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Top
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-pt": [{
          "scroll-pt": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Right
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-pr": [{
          "scroll-pr": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Bottom
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-pb": [{
          "scroll-pb": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Padding Left
         * @see https://tailwindcss.com/docs/scroll-padding
         */
        "scroll-pl": [{
          "scroll-pl": getSpacingWithArbitrary()
        }],
        /**
         * Scroll Snap Align
         * @see https://tailwindcss.com/docs/scroll-snap-align
         */
        "snap-align": [{
          snap: ["start", "end", "center", "align-none"]
        }],
        /**
         * Scroll Snap Stop
         * @see https://tailwindcss.com/docs/scroll-snap-stop
         */
        "snap-stop": [{
          snap: ["normal", "always"]
        }],
        /**
         * Scroll Snap Type
         * @see https://tailwindcss.com/docs/scroll-snap-type
         */
        "snap-type": [{
          snap: ["none", "x", "y", "both"]
        }],
        /**
         * Scroll Snap Type Strictness
         * @see https://tailwindcss.com/docs/scroll-snap-type
         */
        "snap-strictness": [{
          snap: ["mandatory", "proximity"]
        }],
        /**
         * Touch Action
         * @see https://tailwindcss.com/docs/touch-action
         */
        touch: [{
          touch: ["auto", "none", "manipulation"]
        }],
        /**
         * Touch Action X
         * @see https://tailwindcss.com/docs/touch-action
         */
        "touch-x": [{
          "touch-pan": ["x", "left", "right"]
        }],
        /**
         * Touch Action Y
         * @see https://tailwindcss.com/docs/touch-action
         */
        "touch-y": [{
          "touch-pan": ["y", "up", "down"]
        }],
        /**
         * Touch Action Pinch Zoom
         * @see https://tailwindcss.com/docs/touch-action
         */
        "touch-pz": ["touch-pinch-zoom"],
        /**
         * User Select
         * @see https://tailwindcss.com/docs/user-select
         */
        select: [{
          select: ["none", "text", "all", "auto"]
        }],
        /**
         * Will Change
         * @see https://tailwindcss.com/docs/will-change
         */
        "will-change": [{
          "will-change": ["auto", "scroll", "contents", "transform", isArbitraryValue]
        }],
        // SVG
        /**
         * Fill
         * @see https://tailwindcss.com/docs/fill
         */
        fill: [{
          fill: [colors, "none"]
        }],
        /**
         * Stroke Width
         * @see https://tailwindcss.com/docs/stroke-width
         */
        "stroke-w": [{
          stroke: [isLength, isArbitraryLength, isArbitraryNumber]
        }],
        /**
         * Stroke
         * @see https://tailwindcss.com/docs/stroke
         */
        stroke: [{
          stroke: [colors, "none"]
        }],
        // Accessibility
        /**
         * Screen Readers
         * @see https://tailwindcss.com/docs/screen-readers
         */
        sr: ["sr-only", "not-sr-only"],
        /**
         * Forced Color Adjust
         * @see https://tailwindcss.com/docs/forced-color-adjust
         */
        "forced-color-adjust": [{
          "forced-color-adjust": ["auto", "none"]
        }]
      },
      conflictingClassGroups: {
        overflow: ["overflow-x", "overflow-y"],
        overscroll: ["overscroll-x", "overscroll-y"],
        inset: ["inset-x", "inset-y", "start", "end", "top", "right", "bottom", "left"],
        "inset-x": ["right", "left"],
        "inset-y": ["top", "bottom"],
        flex: ["basis", "grow", "shrink"],
        gap: ["gap-x", "gap-y"],
        p: ["px", "py", "ps", "pe", "pt", "pr", "pb", "pl"],
        px: ["pr", "pl"],
        py: ["pt", "pb"],
        m: ["mx", "my", "ms", "me", "mt", "mr", "mb", "ml"],
        mx: ["mr", "ml"],
        my: ["mt", "mb"],
        size: ["w", "h"],
        "font-size": ["leading"],
        "fvn-normal": ["fvn-ordinal", "fvn-slashed-zero", "fvn-figure", "fvn-spacing", "fvn-fraction"],
        "fvn-ordinal": ["fvn-normal"],
        "fvn-slashed-zero": ["fvn-normal"],
        "fvn-figure": ["fvn-normal"],
        "fvn-spacing": ["fvn-normal"],
        "fvn-fraction": ["fvn-normal"],
        "line-clamp": ["display", "overflow"],
        rounded: ["rounded-s", "rounded-e", "rounded-t", "rounded-r", "rounded-b", "rounded-l", "rounded-ss", "rounded-se", "rounded-ee", "rounded-es", "rounded-tl", "rounded-tr", "rounded-br", "rounded-bl"],
        "rounded-s": ["rounded-ss", "rounded-es"],
        "rounded-e": ["rounded-se", "rounded-ee"],
        "rounded-t": ["rounded-tl", "rounded-tr"],
        "rounded-r": ["rounded-tr", "rounded-br"],
        "rounded-b": ["rounded-br", "rounded-bl"],
        "rounded-l": ["rounded-tl", "rounded-bl"],
        "border-spacing": ["border-spacing-x", "border-spacing-y"],
        "border-w": ["border-w-s", "border-w-e", "border-w-t", "border-w-r", "border-w-b", "border-w-l"],
        "border-w-x": ["border-w-r", "border-w-l"],
        "border-w-y": ["border-w-t", "border-w-b"],
        "border-color": ["border-color-s", "border-color-e", "border-color-t", "border-color-r", "border-color-b", "border-color-l"],
        "border-color-x": ["border-color-r", "border-color-l"],
        "border-color-y": ["border-color-t", "border-color-b"],
        "scroll-m": ["scroll-mx", "scroll-my", "scroll-ms", "scroll-me", "scroll-mt", "scroll-mr", "scroll-mb", "scroll-ml"],
        "scroll-mx": ["scroll-mr", "scroll-ml"],
        "scroll-my": ["scroll-mt", "scroll-mb"],
        "scroll-p": ["scroll-px", "scroll-py", "scroll-ps", "scroll-pe", "scroll-pt", "scroll-pr", "scroll-pb", "scroll-pl"],
        "scroll-px": ["scroll-pr", "scroll-pl"],
        "scroll-py": ["scroll-pt", "scroll-pb"],
        touch: ["touch-x", "touch-y", "touch-pz"],
        "touch-x": ["touch"],
        "touch-y": ["touch"],
        "touch-pz": ["touch"]
      },
      conflictingClassGroupModifiers: {
        "font-size": ["leading"]
      }
    };
  };
  var twMerge = /* @__PURE__ */ createTailwindMerge(getDefaultConfig);

  // web/src/lib/cn.ts
  function cn(...inputs) {
    return twMerge(clsx(inputs));
  }

  // web/src/components/shared/AppFrame.tsx
  function AppFrame({ headerRight, children, className }) {
    return /* @__PURE__ */ React.createElement("div", { className: cn("min-h-screen bg-background text-foreground", className) }, /* @__PURE__ */ React.createElement("header", { className: "flex items-center justify-between border-b border-border px-6 py-3" }, /* @__PURE__ */ React.createElement("div", { className: "flex items-center gap-2" }, /* @__PURE__ */ React.createElement("span", { className: "text-sm font-semibold tracking-tight" }, "RoastPilot"), /* @__PURE__ */ React.createElement("span", { className: "text-xs text-muted-foreground" }, "device console")), /* @__PURE__ */ React.createElement("div", { className: "flex items-center gap-3", "data-testid": "header-right" }, headerRight)), /* @__PURE__ */ React.createElement("main", { className: "px-6 py-4" }, children));
  }

  // web/src/components/shared/VerdictBadge.tsx
  init_define_import_meta_env();

  // web/src/lib/verdict.ts
  init_define_import_meta_env();
  function verdictBadge(verdict) {
    switch (verdict) {
      case "allow":
        return { label: "ALLOW", tone: "nominal" };
      case "clamp":
        return { label: "CLAMP", tone: "caution" };
      case "reject":
        return { label: "REJECT", tone: "fault" };
      case "recovery":
      case "fault":
      case "emergency_stop":
        return null;
    }
  }

  // web/src/components/shared/VerdictBadge.tsx
  var TONE_CLASS = {
    nominal: "border-roast-nominal/40 bg-roast-nominal/15 text-roast-nominal",
    caution: "border-roast-caution/40 bg-roast-caution/15 text-roast-caution",
    fault: "border-roast-fault/40 bg-roast-fault/15 text-roast-fault"
  };
  function VerdictBadge({ verdict, className }) {
    const spec = verdictBadge(verdict);
    if (spec === null) return null;
    return /* @__PURE__ */ React.createElement(
      "span",
      {
        "data-testid": "verdict-badge",
        "data-verdict": verdict,
        "data-tone": spec.tone,
        className: cn(
          "inline-flex items-center rounded-md border px-2 py-0.5 text-xs font-semibold uppercase tracking-wide",
          TONE_CLASS[spec.tone],
          className
        )
      },
      spec.label
    );
  }

  // web/src/components/shared/ConnectionIndicator.tsx
  init_define_import_meta_env();
  var STATUS_META = {
    connecting: {
      label: "Connecting",
      dot: "bg-muted-foreground",
      text: "text-muted-foreground"
    },
    live: {
      label: "Live",
      dot: "bg-roast-nominal",
      text: "text-roast-nominal"
    },
    reconnecting: {
      label: "Reconnecting",
      dot: "bg-roast-caution animate-pulse",
      text: "text-roast-caution"
    },
    stale: {
      label: "Stale",
      dot: "bg-roast-fault",
      text: "text-roast-fault"
    }
  };
  function ConnectionIndicator({
    status,
    className
  }) {
    const meta = STATUS_META[status];
    return /* @__PURE__ */ React.createElement(
      "span",
      {
        "data-testid": "connection-indicator",
        "data-status": status,
        className: cn(
          "inline-flex items-center gap-1.5 text-xs font-medium",
          meta.text,
          className
        )
      },
      /* @__PURE__ */ React.createElement("span", { className: cn("size-2 rounded-full", meta.dot), "aria-hidden": true }),
      meta.label
    );
  }

  // web/src/components/shared/LiveCurve/LiveCurve.tsx
  init_define_import_meta_env();
  var import_react = __toESM(require_react_shim());

  // web/node_modules/uplot/dist/uPlot.esm.js
  init_define_import_meta_env();
  var FEAT_TIME = true;
  var pre = "u-";
  var UPLOT = "uplot";
  var ORI_HZ = pre + "hz";
  var ORI_VT = pre + "vt";
  var TITLE = pre + "title";
  var WRAP = pre + "wrap";
  var UNDER = pre + "under";
  var OVER = pre + "over";
  var AXIS = pre + "axis";
  var OFF = pre + "off";
  var SELECT = pre + "select";
  var CURSOR_X = pre + "cursor-x";
  var CURSOR_Y = pre + "cursor-y";
  var CURSOR_PT = pre + "cursor-pt";
  var LEGEND = pre + "legend";
  var LEGEND_LIVE = pre + "live";
  var LEGEND_INLINE = pre + "inline";
  var LEGEND_SERIES = pre + "series";
  var LEGEND_MARKER = pre + "marker";
  var LEGEND_LABEL = pre + "label";
  var LEGEND_VALUE = pre + "value";
  var WIDTH = "width";
  var HEIGHT = "height";
  var TOP = "top";
  var BOTTOM = "bottom";
  var LEFT = "left";
  var RIGHT = "right";
  var hexBlack = "#000";
  var transparent = hexBlack + "0";
  var mousemove = "mousemove";
  var mousedown = "mousedown";
  var mouseup = "mouseup";
  var mouseenter = "mouseenter";
  var mouseleave = "mouseleave";
  var dblclick = "dblclick";
  var resize = "resize";
  var scroll = "scroll";
  var change = "change";
  var dppxchange = "dppxchange";
  var LEGEND_DISP = "--";
  var domEnv = typeof window != "undefined";
  var doc = domEnv ? document : null;
  var win = domEnv ? window : null;
  var nav = domEnv ? navigator : null;
  var pxRatio;
  var query;
  function setPxRatio() {
    let _pxRatio = devicePixelRatio;
    if (pxRatio != _pxRatio) {
      pxRatio = _pxRatio;
      query && off(change, query, setPxRatio);
      query = matchMedia(`(min-resolution: ${pxRatio - 1e-3}dppx) and (max-resolution: ${pxRatio + 1e-3}dppx)`);
      on(change, query, setPxRatio);
      win.dispatchEvent(new CustomEvent(dppxchange));
    }
  }
  function addClass(el, c) {
    if (c != null) {
      let cl = el.classList;
      !cl.contains(c) && cl.add(c);
    }
  }
  function remClass(el, c) {
    let cl = el.classList;
    cl.contains(c) && cl.remove(c);
  }
  function setStylePx(el, name, value) {
    el.style[name] = value + "px";
  }
  function placeTag(tag, cls, targ, refEl) {
    let el = doc.createElement(tag);
    if (cls != null)
      addClass(el, cls);
    if (targ != null)
      targ.insertBefore(el, refEl);
    return el;
  }
  function placeDiv(cls, targ) {
    return placeTag("div", cls, targ);
  }
  var xformCache = /* @__PURE__ */ new WeakMap();
  function elTrans(el, xPos, yPos, xMax, yMax) {
    let xform = "translate(" + xPos + "px," + yPos + "px)";
    let xformOld = xformCache.get(el);
    if (xform != xformOld) {
      el.style.transform = xform;
      xformCache.set(el, xform);
      if (xPos < 0 || yPos < 0 || xPos > xMax || yPos > yMax)
        addClass(el, OFF);
      else
        remClass(el, OFF);
    }
  }
  var colorCache = /* @__PURE__ */ new WeakMap();
  function elColor(el, background, borderColor) {
    let newColor = background + borderColor;
    let oldColor = colorCache.get(el);
    if (newColor != oldColor) {
      colorCache.set(el, newColor);
      el.style.background = background;
      el.style.borderColor = borderColor;
    }
  }
  var sizeCache = /* @__PURE__ */ new WeakMap();
  function elSize(el, newWid, newHgt, centered) {
    let newSize = newWid + "" + newHgt;
    let oldSize = sizeCache.get(el);
    if (newSize != oldSize) {
      sizeCache.set(el, newSize);
      el.style.height = newHgt + "px";
      el.style.width = newWid + "px";
      el.style.marginLeft = centered ? -newWid / 2 + "px" : 0;
      el.style.marginTop = centered ? -newHgt / 2 + "px" : 0;
    }
  }
  var evOpts = { passive: true };
  var evOpts2 = { ...evOpts, capture: true };
  function on(ev, el, cb, capt) {
    el.addEventListener(ev, cb, capt ? evOpts2 : evOpts);
  }
  function off(ev, el, cb, capt) {
    el.removeEventListener(ev, cb, evOpts);
  }
  domEnv && setPxRatio();
  function closestIdx(num, arr, lo, hi) {
    let mid;
    lo = lo || 0;
    hi = hi || arr.length - 1;
    let bitwise = hi <= 2147483647;
    while (hi - lo > 1) {
      mid = bitwise ? lo + hi >> 1 : floor((lo + hi) / 2);
      if (arr[mid] < num)
        lo = mid;
      else
        hi = mid;
    }
    if (num - arr[lo] <= arr[hi] - num)
      return lo;
    return hi;
  }
  function makeIndexOfs(predicate) {
    let indexOfs = (data, _i0, _i1) => {
      let i0 = -1;
      let i1 = -1;
      for (let i = _i0; i <= _i1; i++) {
        if (predicate(data[i])) {
          i0 = i;
          break;
        }
      }
      for (let i = _i1; i >= _i0; i--) {
        if (predicate(data[i])) {
          i1 = i;
          break;
        }
      }
      return [i0, i1];
    };
    return indexOfs;
  }
  var notNullish = (v) => v != null;
  var isPositive = (v) => v != null && v > 0;
  var nonNullIdxs = makeIndexOfs(notNullish);
  var positiveIdxs = makeIndexOfs(isPositive);
  function getMinMax(data, _i0, _i1, sorted = 0, log = false) {
    let getEdgeIdxs = log ? positiveIdxs : nonNullIdxs;
    let predicate = log ? isPositive : notNullish;
    [_i0, _i1] = getEdgeIdxs(data, _i0, _i1);
    let _min = data[_i0];
    let _max = data[_i0];
    if (_i0 > -1) {
      if (sorted == 1) {
        _min = data[_i0];
        _max = data[_i1];
      } else if (sorted == -1) {
        _min = data[_i1];
        _max = data[_i0];
      } else {
        for (let i = _i0; i <= _i1; i++) {
          let v = data[i];
          if (predicate(v)) {
            if (v < _min)
              _min = v;
            else if (v > _max)
              _max = v;
          }
        }
      }
    }
    return [_min ?? inf, _max ?? -inf];
  }
  function rangeLog(min2, max2, base, fullMags) {
    let minSign = sign(min2);
    let maxSign = sign(max2);
    if (min2 == max2) {
      if (minSign == -1) {
        min2 *= base;
        max2 /= base;
      } else {
        min2 /= base;
        max2 *= base;
      }
    }
    let logFn = base == 10 ? log10 : log2;
    let growMinAbs = minSign == 1 ? floor : ceil;
    let growMaxAbs = maxSign == 1 ? ceil : floor;
    let minExp = growMinAbs(logFn(abs(min2)));
    let maxExp = growMaxAbs(logFn(abs(max2)));
    let minIncr = pow(base, minExp);
    let maxIncr = pow(base, maxExp);
    if (base == 10) {
      if (minExp < 0)
        minIncr = roundDec(minIncr, -minExp);
      if (maxExp < 0)
        maxIncr = roundDec(maxIncr, -maxExp);
    }
    if (fullMags || base == 2) {
      min2 = minIncr * minSign;
      max2 = maxIncr * maxSign;
    } else {
      min2 = incrRoundDn(min2, minIncr);
      max2 = incrRoundUp(max2, maxIncr);
    }
    return [min2, max2];
  }
  function rangeAsinh(min2, max2, base, fullMags) {
    let minMax = rangeLog(min2, max2, base, fullMags);
    if (min2 == 0)
      minMax[0] = 0;
    if (max2 == 0)
      minMax[1] = 0;
    return minMax;
  }
  var rangePad = 0.1;
  var autoRangePart = {
    mode: 3,
    pad: rangePad
  };
  var _eqRangePart = {
    pad: 0,
    soft: null,
    mode: 0
  };
  var _eqRange = {
    min: _eqRangePart,
    max: _eqRangePart
  };
  function rangeNum(_min, _max, mult, extra) {
    if (isObj(mult))
      return _rangeNum(_min, _max, mult);
    _eqRangePart.pad = mult;
    _eqRangePart.soft = extra ? 0 : null;
    _eqRangePart.mode = extra ? 3 : 0;
    return _rangeNum(_min, _max, _eqRange);
  }
  function ifNull(lh, rh) {
    return lh == null ? rh : lh;
  }
  function hasData(data, idx0, idx1) {
    idx0 = ifNull(idx0, 0);
    idx1 = ifNull(idx1, data.length - 1);
    while (idx0 <= idx1) {
      if (data[idx0] != null)
        return true;
      idx0++;
    }
    return false;
  }
  function _rangeNum(_min, _max, cfg) {
    let cmin = cfg.min;
    let cmax = cfg.max;
    let padMin = ifNull(cmin.pad, 0);
    let padMax = ifNull(cmax.pad, 0);
    let hardMin = ifNull(cmin.hard, -inf);
    let hardMax = ifNull(cmax.hard, inf);
    let softMin = ifNull(cmin.soft, inf);
    let softMax = ifNull(cmax.soft, -inf);
    let softMinMode = ifNull(cmin.mode, 0);
    let softMaxMode = ifNull(cmax.mode, 0);
    let delta = _max - _min;
    let deltaMag = log10(delta);
    let scalarMax = max(abs(_min), abs(_max));
    let scalarMag = log10(scalarMax);
    let scalarMagDelta = abs(scalarMag - deltaMag);
    if (delta < 1e-24 || scalarMagDelta > 10) {
      delta = 0;
      if (_min == 0 || _max == 0) {
        delta = 1e-24;
        if (softMinMode == 2 && softMin != inf)
          padMin = 0;
        if (softMaxMode == 2 && softMax != -inf)
          padMax = 0;
      }
    }
    let nonZeroDelta = delta || scalarMax || 1e3;
    let mag = log10(nonZeroDelta);
    let base = pow(10, floor(mag));
    let _padMin = nonZeroDelta * (delta == 0 ? _min == 0 ? 0.1 : 1 : padMin);
    let _newMin = roundDec(incrRoundDn(_min - _padMin, base / 10), 24);
    let _softMin = _min >= softMin && (softMinMode == 1 || softMinMode == 3 && _newMin <= softMin || softMinMode == 2 && _newMin >= softMin) ? softMin : inf;
    let minLim = max(hardMin, _newMin < _softMin && _min >= _softMin ? _softMin : min(_softMin, _newMin));
    let _padMax = nonZeroDelta * (delta == 0 ? _max == 0 ? 0.1 : 1 : padMax);
    let _newMax = roundDec(incrRoundUp(_max + _padMax, base / 10), 24);
    let _softMax = _max <= softMax && (softMaxMode == 1 || softMaxMode == 3 && _newMax >= softMax || softMaxMode == 2 && _newMax <= softMax) ? softMax : -inf;
    let maxLim = min(hardMax, _newMax > _softMax && _max <= _softMax ? _softMax : max(_softMax, _newMax));
    if (minLim == maxLim && minLim == 0)
      maxLim = 100;
    return [minLim, maxLim];
  }
  var numFormatter = new Intl.NumberFormat(domEnv ? nav.language : "en-US");
  var fmtNum = (val) => numFormatter.format(val);
  var M = Math;
  var PI = M.PI;
  var abs = M.abs;
  var floor = M.floor;
  var round = M.round;
  var ceil = M.ceil;
  var min = M.min;
  var max = M.max;
  var pow = M.pow;
  var sign = M.sign;
  var log10 = M.log10;
  var log2 = M.log2;
  var sinh = (v, linthresh = 1) => M.sinh(v) * linthresh;
  var asinh = (v, linthresh = 1) => M.asinh(v / linthresh);
  var inf = Infinity;
  function numIntDigits(x) {
    return (log10((x ^ x >> 31) - (x >> 31)) | 0) + 1;
  }
  function clamp(num, _min, _max) {
    return min(max(num, _min), _max);
  }
  function isFn(v) {
    return typeof v == "function";
  }
  function fnOrSelf(v) {
    return isFn(v) ? v : () => v;
  }
  var noop = () => {
  };
  var retArg0 = (_0) => _0;
  var retArg1 = (_0, _1) => _1;
  var retNull = (_2) => null;
  var retTrue = (_2) => true;
  var retEq = (a, b) => a == b;
  var regex6 = /\.\d*?(?=9{6,}|0{6,})/gm;
  var fixFloat = (val) => {
    if (isInt(val) || fixedDec.has(val))
      return val;
    const str = `${val}`;
    const match = str.match(regex6);
    if (match == null)
      return val;
    let len = match[0].length - 1;
    if (str.indexOf("e-") != -1) {
      let [num, exp] = str.split("e");
      return +`${fixFloat(num)}e${exp}`;
    }
    return roundDec(val, len);
  };
  function incrRound(num, incr) {
    return fixFloat(roundDec(fixFloat(num / incr)) * incr);
  }
  function incrRoundUp(num, incr) {
    return fixFloat(ceil(fixFloat(num / incr)) * incr);
  }
  function incrRoundDn(num, incr) {
    return fixFloat(floor(fixFloat(num / incr)) * incr);
  }
  function roundDec(val, dec = 0) {
    if (isInt(val))
      return val;
    let p = 10 ** dec;
    let n = val * p * (1 + Number.EPSILON);
    return round(n) / p;
  }
  var fixedDec = /* @__PURE__ */ new Map();
  function guessDec(num) {
    return (("" + num).split(".")[1] || "").length;
  }
  function genIncrs(base, minExp, maxExp, mults) {
    let incrs = [];
    let multDec = mults.map(guessDec);
    for (let exp = minExp; exp < maxExp; exp++) {
      let expa = abs(exp);
      let mag = roundDec(pow(base, exp), expa);
      for (let i = 0; i < mults.length; i++) {
        let _incr = base == 10 ? +`${mults[i]}e${exp}` : mults[i] * mag;
        let dec = (exp >= 0 ? 0 : expa) + (exp >= multDec[i] ? 0 : multDec[i]);
        let incr = base == 10 ? _incr : roundDec(_incr, dec);
        incrs.push(incr);
        fixedDec.set(incr, dec);
      }
    }
    return incrs;
  }
  var EMPTY_OBJ = {};
  var EMPTY_ARR = [];
  var nullNullTuple = [null, null];
  var isArr = Array.isArray;
  var isInt = Number.isInteger;
  var isUndef = (v) => v === void 0;
  function isStr(v) {
    return typeof v == "string";
  }
  function isObj(v) {
    let is = false;
    if (v != null) {
      let c = v.constructor;
      is = c == null || c == Object;
    }
    return is;
  }
  function fastIsObj(v) {
    return v != null && typeof v == "object";
  }
  var TypedArray = Object.getPrototypeOf(Uint8Array);
  var __proto__ = "__proto__";
  function copy(o, _isObj = isObj) {
    let out;
    if (isArr(o)) {
      let val = o.find((v) => v != null);
      if (isArr(val) || _isObj(val)) {
        out = Array(o.length);
        for (let i = 0; i < o.length; i++)
          out[i] = copy(o[i], _isObj);
      } else
        out = o.slice();
    } else if (o instanceof TypedArray)
      out = o.slice();
    else if (_isObj(o)) {
      out = {};
      for (let k in o) {
        if (k != __proto__)
          out[k] = copy(o[k], _isObj);
      }
    } else
      out = o;
    return out;
  }
  function assign(targ) {
    let args = arguments;
    for (let i = 1; i < args.length; i++) {
      let src = args[i];
      for (let key in src) {
        if (key != __proto__) {
          if (isObj(targ[key]))
            assign(targ[key], copy(src[key]));
          else
            targ[key] = copy(src[key]);
        }
      }
    }
    return targ;
  }
  var NULL_REMOVE = 0;
  var NULL_RETAIN = 1;
  var NULL_EXPAND = 2;
  function nullExpand(yVals, nullIdxs, alignedLen) {
    for (let i = 0, xi, lastNullIdx = -1; i < nullIdxs.length; i++) {
      let nullIdx = nullIdxs[i];
      if (nullIdx > lastNullIdx) {
        xi = nullIdx - 1;
        while (xi >= 0 && yVals[xi] == null)
          yVals[xi--] = null;
        xi = nullIdx + 1;
        while (xi < alignedLen && yVals[xi] == null)
          yVals[lastNullIdx = xi++] = null;
      }
    }
  }
  function join(tables, nullModes) {
    if (allHeadersSame(tables)) {
      let table = tables[0].slice();
      for (let i = 1; i < tables.length; i++)
        table.push(...tables[i].slice(1));
      if (!isAsc(table[0]))
        table = sortCols(table);
      return table;
    }
    let xVals = /* @__PURE__ */ new Set();
    for (let ti = 0; ti < tables.length; ti++) {
      let t = tables[ti];
      let xs = t[0];
      let len = xs.length;
      for (let i = 0; i < len; i++)
        xVals.add(xs[i]);
    }
    let data = [Array.from(xVals).sort((a, b) => a - b)];
    let alignedLen = data[0].length;
    let xIdxs = /* @__PURE__ */ new Map();
    for (let i = 0; i < alignedLen; i++)
      xIdxs.set(data[0][i], i);
    for (let ti = 0; ti < tables.length; ti++) {
      let t = tables[ti];
      let xs = t[0];
      for (let si = 1; si < t.length; si++) {
        let ys = t[si];
        let yVals = Array(alignedLen).fill(void 0);
        let nullMode = nullModes ? nullModes[ti][si] : NULL_RETAIN;
        let nullIdxs = [];
        for (let i = 0; i < ys.length; i++) {
          let yVal = ys[i];
          let alignedIdx = xIdxs.get(xs[i]);
          if (yVal === null) {
            if (nullMode != NULL_REMOVE) {
              yVals[alignedIdx] = yVal;
              if (nullMode == NULL_EXPAND)
                nullIdxs.push(alignedIdx);
            }
          } else
            yVals[alignedIdx] = yVal;
        }
        nullExpand(yVals, nullIdxs, alignedLen);
        data.push(yVals);
      }
    }
    return data;
  }
  var microTask = typeof queueMicrotask == "undefined" ? (fn) => Promise.resolve().then(fn) : queueMicrotask;
  function sortCols(table) {
    let head = table[0];
    let rlen = head.length;
    let idxs = Array(rlen);
    for (let i = 0; i < idxs.length; i++)
      idxs[i] = i;
    idxs.sort((i0, i1) => head[i0] - head[i1]);
    let table2 = [];
    for (let i = 0; i < table.length; i++) {
      let row = table[i];
      let row2 = Array(rlen);
      for (let j = 0; j < rlen; j++)
        row2[j] = row[idxs[j]];
      table2.push(row2);
    }
    return table2;
  }
  function allHeadersSame(tables) {
    let vals0 = tables[0][0];
    let len0 = vals0.length;
    for (let i = 1; i < tables.length; i++) {
      let vals1 = tables[i][0];
      if (vals1.length != len0)
        return false;
      if (vals1 != vals0) {
        for (let j = 0; j < len0; j++) {
          if (vals1[j] != vals0[j])
            return false;
        }
      }
    }
    return true;
  }
  function isAsc(vals, samples = 100) {
    const len = vals.length;
    if (len <= 1)
      return true;
    let firstIdx = 0;
    let lastIdx = len - 1;
    while (firstIdx <= lastIdx && vals[firstIdx] == null)
      firstIdx++;
    while (lastIdx >= firstIdx && vals[lastIdx] == null)
      lastIdx--;
    if (lastIdx <= firstIdx)
      return true;
    const stride = max(1, floor((lastIdx - firstIdx + 1) / samples));
    for (let prevVal = vals[firstIdx], i = firstIdx + stride; i <= lastIdx; i += stride) {
      const v = vals[i];
      if (v != null) {
        if (v <= prevVal)
          return false;
        prevVal = v;
      }
    }
    return true;
  }
  var months = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December"
  ];
  var days = [
    "Sunday",
    "Monday",
    "Tuesday",
    "Wednesday",
    "Thursday",
    "Friday",
    "Saturday"
  ];
  function slice3(str) {
    return str.slice(0, 3);
  }
  var days3 = days.map(slice3);
  var months3 = months.map(slice3);
  var engNames = {
    MMMM: months,
    MMM: months3,
    WWWW: days,
    WWW: days3
  };
  function zeroPad2(int) {
    return (int < 10 ? "0" : "") + int;
  }
  function zeroPad3(int) {
    return (int < 10 ? "00" : int < 100 ? "0" : "") + int;
  }
  var subs = {
    // 2019
    YYYY: (d) => d.getFullYear(),
    // 19
    YY: (d) => (d.getFullYear() + "").slice(2),
    // July
    MMMM: (d, names) => names.MMMM[d.getMonth()],
    // Jul
    MMM: (d, names) => names.MMM[d.getMonth()],
    // 07
    MM: (d) => zeroPad2(d.getMonth() + 1),
    // 7
    M: (d) => d.getMonth() + 1,
    // 09
    DD: (d) => zeroPad2(d.getDate()),
    // 9
    D: (d) => d.getDate(),
    // Monday
    WWWW: (d, names) => names.WWWW[d.getDay()],
    // Mon
    WWW: (d, names) => names.WWW[d.getDay()],
    // 03
    HH: (d) => zeroPad2(d.getHours()),
    // 3
    H: (d) => d.getHours(),
    // 9 (12hr, unpadded)
    h: (d) => {
      let h = d.getHours();
      return h == 0 ? 12 : h > 12 ? h - 12 : h;
    },
    // AM
    AA: (d) => d.getHours() >= 12 ? "PM" : "AM",
    // am
    aa: (d) => d.getHours() >= 12 ? "pm" : "am",
    // a
    a: (d) => d.getHours() >= 12 ? "p" : "a",
    // 09
    mm: (d) => zeroPad2(d.getMinutes()),
    // 9
    m: (d) => d.getMinutes(),
    // 09
    ss: (d) => zeroPad2(d.getSeconds()),
    // 9
    s: (d) => d.getSeconds(),
    // 374
    fff: (d) => zeroPad3(d.getMilliseconds())
  };
  function fmtDate(tpl, names) {
    names = names || engNames;
    let parts = [];
    let R = /\{([a-z]+)\}|[^{]+/gi, m;
    while (m = R.exec(tpl))
      parts.push(m[0][0] == "{" ? subs[m[1]] : m[0]);
    return (d) => {
      let out = "";
      for (let i = 0; i < parts.length; i++)
        out += typeof parts[i] == "string" ? parts[i] : parts[i](d, names);
      return out;
    };
  }
  var localTz = new Intl.DateTimeFormat().resolvedOptions().timeZone;
  function tzDate(date, tz) {
    let date2;
    if (tz == "UTC" || tz == "Etc/UTC")
      date2 = new Date(+date + date.getTimezoneOffset() * 6e4);
    else if (tz == localTz)
      date2 = date;
    else {
      date2 = new Date(date.toLocaleString("en-US", { timeZone: tz }));
      date2.setMilliseconds(date.getMilliseconds());
    }
    return date2;
  }
  var onlyWhole = (v) => v % 1 == 0;
  var allMults = [1, 2, 2.5, 5];
  var decIncrs = genIncrs(10, -32, 0, allMults);
  var oneIncrs = genIncrs(10, 0, 32, allMults);
  var wholeIncrs = oneIncrs.filter(onlyWhole);
  var numIncrs = decIncrs.concat(oneIncrs);
  var NL = "\n";
  var yyyy = "{YYYY}";
  var NLyyyy = NL + yyyy;
  var md = "{M}/{D}";
  var NLmd = NL + md;
  var NLmdyy = NLmd + "/{YY}";
  var aa = "{aa}";
  var hmm = "{h}:{mm}";
  var hmmaa = hmm + aa;
  var NLhmmaa = NL + hmmaa;
  var ss = ":{ss}";
  var _ = null;
  function genTimeStuffs(ms) {
    let s = ms * 1e3, m = s * 60, h = m * 60, d = h * 24, mo = d * 30, y = d * 365;
    let subSecIncrs = ms == 1 ? genIncrs(10, 0, 3, allMults).filter(onlyWhole) : genIncrs(10, -3, 0, allMults);
    let timeIncrs = subSecIncrs.concat([
      // minute divisors (# of secs)
      s,
      s * 5,
      s * 10,
      s * 15,
      s * 30,
      // hour divisors (# of mins)
      m,
      m * 5,
      m * 10,
      m * 15,
      m * 30,
      // day divisors (# of hrs)
      h,
      h * 2,
      h * 3,
      h * 4,
      h * 6,
      h * 8,
      h * 12,
      // month divisors TODO: need more?
      d,
      d * 2,
      d * 3,
      d * 4,
      d * 5,
      d * 6,
      d * 7,
      d * 8,
      d * 9,
      d * 10,
      d * 15,
      // year divisors (# months, approx)
      mo,
      mo * 2,
      mo * 3,
      mo * 4,
      mo * 6,
      // century divisors
      y,
      y * 2,
      y * 5,
      y * 10,
      y * 25,
      y * 50,
      y * 100
    ]);
    const _timeAxisStamps = [
      //   tick incr    default          year                    month   day                   hour    min       sec   mode
      [y, yyyy, _, _, _, _, _, _, 1],
      [d * 28, "{MMM}", NLyyyy, _, _, _, _, _, 1],
      [d, md, NLyyyy, _, _, _, _, _, 1],
      [h, "{h}" + aa, NLmdyy, _, NLmd, _, _, _, 1],
      [m, hmmaa, NLmdyy, _, NLmd, _, _, _, 1],
      [s, ss, NLmdyy + " " + hmmaa, _, NLmd + " " + hmmaa, _, NLhmmaa, _, 1],
      [ms, ss + ".{fff}", NLmdyy + " " + hmmaa, _, NLmd + " " + hmmaa, _, NLhmmaa, _, 1]
    ];
    function timeAxisSplits(tzDate2) {
      return (self, axisIdx, scaleMin, scaleMax, foundIncr, foundSpace) => {
        let splits = [];
        let isYr = foundIncr >= y;
        let isMo = foundIncr >= mo && foundIncr < y;
        let minDate = tzDate2(scaleMin);
        let minDateTs = roundDec(minDate * ms, 3);
        let minMin = mkDate(minDate.getFullYear(), isYr ? 0 : minDate.getMonth(), isMo || isYr ? 1 : minDate.getDate());
        let minMinTs = roundDec(minMin * ms, 3);
        if (isMo || isYr) {
          let moIncr = isMo ? foundIncr / mo : 0;
          let yrIncr = isYr ? foundIncr / y : 0;
          let split = minDateTs == minMinTs ? minDateTs : roundDec(mkDate(minMin.getFullYear() + yrIncr, minMin.getMonth() + moIncr, 1) * ms, 3);
          let splitDate = new Date(round(split / ms));
          let baseYear = splitDate.getFullYear();
          let baseMonth = splitDate.getMonth();
          for (let i = 0; split <= scaleMax; i++) {
            let next = mkDate(baseYear + yrIncr * i, baseMonth + moIncr * i, 1);
            let offs = next - tzDate2(roundDec(next * ms, 3));
            split = roundDec((+next + offs) * ms, 3);
            if (split <= scaleMax)
              splits.push(split);
          }
        } else {
          let incr0 = foundIncr >= d ? d : foundIncr;
          let tzOffset = floor(scaleMin) - floor(minDateTs);
          let split = minMinTs + tzOffset + incrRoundUp(minDateTs - minMinTs, incr0);
          splits.push(split);
          let date0 = tzDate2(split);
          let prevHour = date0.getHours() + date0.getMinutes() / m + date0.getSeconds() / h;
          let incrHours = foundIncr / h;
          let minSpace = self.axes[axisIdx]._space;
          let pctSpace = foundSpace / minSpace;
          while (1) {
            split = roundDec(split + foundIncr, ms == 1 ? 0 : 3);
            if (split > scaleMax)
              break;
            if (incrHours > 1) {
              let expectedHour = floor(roundDec(prevHour + incrHours, 6)) % 24;
              let splitDate = tzDate2(split);
              let actualHour = splitDate.getHours();
              let dstShift = actualHour - expectedHour;
              if (dstShift > 1)
                dstShift = -1;
              split -= dstShift * h;
              prevHour = (prevHour + incrHours) % 24;
              let prevSplit = splits[splits.length - 1];
              let pctIncr = roundDec((split - prevSplit) / foundIncr, 3);
              if (pctIncr * pctSpace >= 0.7)
                splits.push(split);
            } else
              splits.push(split);
          }
        }
        return splits;
      };
    }
    return [
      timeIncrs,
      _timeAxisStamps,
      timeAxisSplits
    ];
  }
  var [timeIncrsMs, _timeAxisStampsMs, timeAxisSplitsMs] = genTimeStuffs(1);
  var [timeIncrsS, _timeAxisStampsS, timeAxisSplitsS] = genTimeStuffs(1e-3);
  genIncrs(2, -53, 53, [1]);
  function timeAxisStamps(stampCfg, fmtDate2) {
    return stampCfg.map((s) => s.map(
      (v, i) => i == 0 || i == 8 || v == null ? v : fmtDate2(i == 1 || s[8] == 0 ? v : s[1] + v)
    ));
  }
  function timeAxisVals(tzDate2, stamps) {
    return (self, splits, axisIdx, foundSpace, foundIncr) => {
      let s = stamps.find((s2) => foundIncr >= s2[0]) || stamps[stamps.length - 1];
      let prevYear;
      let prevMnth;
      let prevDate;
      let prevHour;
      let prevMins;
      let prevSecs;
      return splits.map((split) => {
        let date = tzDate2(split);
        let newYear = date.getFullYear();
        let newMnth = date.getMonth();
        let newDate = date.getDate();
        let newHour = date.getHours();
        let newMins = date.getMinutes();
        let newSecs = date.getSeconds();
        let stamp = newYear != prevYear && s[2] || newMnth != prevMnth && s[3] || newDate != prevDate && s[4] || newHour != prevHour && s[5] || newMins != prevMins && s[6] || newSecs != prevSecs && s[7] || s[1];
        prevYear = newYear;
        prevMnth = newMnth;
        prevDate = newDate;
        prevHour = newHour;
        prevMins = newMins;
        prevSecs = newSecs;
        return stamp(date);
      });
    };
  }
  function timeAxisVal(tzDate2, dateTpl) {
    let stamp = fmtDate(dateTpl);
    return (self, splits, axisIdx, foundSpace, foundIncr) => splits.map((split) => stamp(tzDate2(split)));
  }
  function mkDate(y, m, d) {
    return new Date(y, m, d);
  }
  function timeSeriesStamp(stampCfg, fmtDate2) {
    return fmtDate2(stampCfg);
  }
  var _timeSeriesStamp = "{YYYY}-{MM}-{DD} {h}:{mm}{aa}";
  function timeSeriesVal(tzDate2, stamp) {
    return (self, val, seriesIdx, dataIdx) => dataIdx == null ? LEGEND_DISP : stamp(tzDate2(val));
  }
  function legendStroke(self, seriesIdx) {
    let s = self.series[seriesIdx];
    return s.width ? s.stroke(self, seriesIdx) : s.points.width ? s.points.stroke(self, seriesIdx) : null;
  }
  function legendFill(self, seriesIdx) {
    return self.series[seriesIdx].fill(self, seriesIdx);
  }
  var legendOpts = {
    show: true,
    live: true,
    isolate: false,
    mount: noop,
    markers: {
      show: true,
      width: 2,
      stroke: legendStroke,
      fill: legendFill,
      dash: "solid"
    },
    idx: null,
    idxs: null,
    values: []
  };
  function cursorPointShow(self, si) {
    let o = self.cursor.points;
    let pt = placeDiv();
    let size = o.size(self, si);
    setStylePx(pt, WIDTH, size);
    setStylePx(pt, HEIGHT, size);
    let mar = size / -2;
    setStylePx(pt, "marginLeft", mar);
    setStylePx(pt, "marginTop", mar);
    let width = o.width(self, si, size);
    width && setStylePx(pt, "borderWidth", width);
    return pt;
  }
  function cursorPointFill(self, si) {
    let sp = self.series[si].points;
    return sp._fill || sp._stroke;
  }
  function cursorPointStroke(self, si) {
    let sp = self.series[si].points;
    return sp._stroke || sp._fill;
  }
  function cursorPointSize(self, si) {
    let sp = self.series[si].points;
    return sp.size;
  }
  var moveTuple = [0, 0];
  function cursorMove(self, mouseLeft1, mouseTop1) {
    moveTuple[0] = mouseLeft1;
    moveTuple[1] = mouseTop1;
    return moveTuple;
  }
  function filtBtn0(self, targ, handle, onlyTarg = true) {
    return (e) => {
      e.button == 0 && (!onlyTarg || e.target == targ) && handle(e);
    };
  }
  function filtTarg(self, targ, handle, onlyTarg = true) {
    return (e) => {
      (!onlyTarg || e.target == targ) && handle(e);
    };
  }
  var cursorOpts = {
    show: true,
    x: true,
    y: true,
    lock: false,
    move: cursorMove,
    points: {
      one: false,
      show: cursorPointShow,
      size: cursorPointSize,
      width: 0,
      stroke: cursorPointStroke,
      fill: cursorPointFill
    },
    bind: {
      mousedown: filtBtn0,
      mouseup: filtBtn0,
      click: filtBtn0,
      // legend clicks, not .u-over clicks
      dblclick: filtBtn0,
      mousemove: filtTarg,
      mouseleave: filtTarg,
      mouseenter: filtTarg
    },
    drag: {
      setScale: true,
      x: true,
      y: false,
      dist: 0,
      uni: null,
      click: (self, e) => {
        e.stopPropagation();
        e.stopImmediatePropagation();
      },
      _x: false,
      _y: false
    },
    focus: {
      dist: (self, seriesIdx, dataIdx, valPos, curPos) => valPos - curPos,
      prox: -1,
      bias: 0
    },
    hover: {
      skip: [void 0],
      prox: null,
      bias: 0
    },
    left: -10,
    top: -10,
    idx: null,
    dataIdx: null,
    idxs: null,
    event: null
  };
  var axisLines = {
    show: true,
    stroke: "rgba(0,0,0,0.07)",
    width: 2
    //	dash: [],
  };
  var grid = assign({}, axisLines, {
    filter: retArg1
  });
  var ticks = assign({}, grid, {
    size: 10
  });
  var border = assign({}, axisLines, {
    show: false
  });
  var font = '12px system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, "Noto Sans", sans-serif, "Apple Color Emoji", "Segoe UI Emoji", "Segoe UI Symbol", "Noto Color Emoji"';
  var labelFont = "bold " + font;
  var lineGap = 1.5;
  var xAxisOpts = {
    show: true,
    scale: "x",
    stroke: hexBlack,
    space: 50,
    gap: 5,
    alignTo: 1,
    size: 50,
    labelGap: 0,
    labelSize: 30,
    labelFont,
    side: 2,
    //	class: "x-vals",
    //	incrs: timeIncrs,
    //	values: timeVals,
    //	filter: retArg1,
    grid,
    ticks,
    border,
    font,
    lineGap,
    rotate: 0
  };
  var numSeriesLabel = "Value";
  var timeSeriesLabel = "Time";
  var xSeriesOpts = {
    show: true,
    scale: "x",
    auto: false,
    sorted: 1,
    //	label: "Time",
    //	value: v => stamp(new Date(v * 1e3)),
    // internal caches
    min: inf,
    max: -inf,
    idxs: []
  };
  function numAxisVals(self, splits, axisIdx, foundSpace, foundIncr) {
    return splits.map((v) => v == null ? "" : fmtNum(v));
  }
  function numAxisSplits(self, axisIdx, scaleMin, scaleMax, foundIncr, foundSpace, forceMin) {
    let splits = [];
    let numDec = fixedDec.get(foundIncr) || 0;
    scaleMin = forceMin ? scaleMin : roundDec(incrRoundUp(scaleMin, foundIncr), numDec);
    for (let val = scaleMin; val <= scaleMax; val = roundDec(val + foundIncr, numDec))
      splits.push(Object.is(val, -0) ? 0 : val);
    return splits;
  }
  function logAxisSplits(self, axisIdx, scaleMin, scaleMax, foundIncr, foundSpace, forceMin) {
    const splits = [];
    const logBase = self.scales[self.axes[axisIdx].scale].log;
    const logFn = logBase == 10 ? log10 : log2;
    const exp = floor(logFn(scaleMin));
    foundIncr = pow(logBase, exp);
    if (logBase == 10)
      foundIncr = numIncrs[closestIdx(foundIncr, numIncrs)];
    let split = scaleMin;
    let nextMagIncr = foundIncr * logBase;
    if (logBase == 10)
      nextMagIncr = numIncrs[closestIdx(nextMagIncr, numIncrs)];
    do {
      splits.push(split);
      split = split + foundIncr;
      if (logBase == 10 && !fixedDec.has(split))
        split = roundDec(split, fixedDec.get(foundIncr));
      if (split >= nextMagIncr) {
        foundIncr = split;
        nextMagIncr = foundIncr * logBase;
        if (logBase == 10)
          nextMagIncr = numIncrs[closestIdx(nextMagIncr, numIncrs)];
      }
    } while (split <= scaleMax);
    return splits;
  }
  function asinhAxisSplits(self, axisIdx, scaleMin, scaleMax, foundIncr, foundSpace, forceMin) {
    let sc = self.scales[self.axes[axisIdx].scale];
    let linthresh = sc.asinh;
    let posSplits = scaleMax > linthresh ? logAxisSplits(self, axisIdx, max(linthresh, scaleMin), scaleMax, foundIncr) : [linthresh];
    let zero = scaleMax >= 0 && scaleMin <= 0 ? [0] : [];
    let negSplits = scaleMin < -linthresh ? logAxisSplits(self, axisIdx, max(linthresh, -scaleMax), -scaleMin, foundIncr) : [linthresh];
    return negSplits.reverse().map((v) => -v).concat(zero, posSplits);
  }
  var RE_ALL = /./;
  var RE_12357 = /[12357]/;
  var RE_125 = /[125]/;
  var RE_1 = /1/;
  var _filt = (splits, distr, re, keepMod) => splits.map((v, i) => distr == 4 && v == 0 || i % keepMod == 0 && re.test(v.toExponential()[v < 0 ? 1 : 0]) ? v : null);
  function log10AxisValsFilt(self, splits, axisIdx, foundSpace, foundIncr) {
    let axis = self.axes[axisIdx];
    let scaleKey = axis.scale;
    let sc = self.scales[scaleKey];
    let valToPos = self.valToPos;
    let minSpace = axis._space;
    let _10 = valToPos(10, scaleKey);
    let re = valToPos(9, scaleKey) - _10 >= minSpace ? RE_ALL : valToPos(7, scaleKey) - _10 >= minSpace ? RE_12357 : valToPos(5, scaleKey) - _10 >= minSpace ? RE_125 : RE_1;
    if (re == RE_1) {
      let magSpace = abs(valToPos(1, scaleKey) - _10);
      if (magSpace < minSpace)
        return _filt(splits.slice().reverse(), sc.distr, re, ceil(minSpace / magSpace)).reverse();
    }
    return _filt(splits, sc.distr, re, 1);
  }
  function log2AxisValsFilt(self, splits, axisIdx, foundSpace, foundIncr) {
    let axis = self.axes[axisIdx];
    let scaleKey = axis.scale;
    let minSpace = axis._space;
    let valToPos = self.valToPos;
    let magSpace = abs(valToPos(1, scaleKey) - valToPos(2, scaleKey));
    if (magSpace < minSpace)
      return _filt(splits.slice().reverse(), 3, RE_ALL, ceil(minSpace / magSpace)).reverse();
    return splits;
  }
  function numSeriesVal(self, val, seriesIdx, dataIdx) {
    return dataIdx == null ? LEGEND_DISP : val == null ? "" : fmtNum(val);
  }
  var yAxisOpts = {
    show: true,
    scale: "y",
    stroke: hexBlack,
    space: 30,
    gap: 5,
    alignTo: 1,
    size: 50,
    labelGap: 0,
    labelSize: 30,
    labelFont,
    side: 3,
    //	class: "y-vals",
    //	incrs: numIncrs,
    //	values: (vals, space) => vals,
    //	filter: retArg1,
    grid,
    ticks,
    border,
    font,
    lineGap,
    rotate: 0
  };
  function ptDia(width, mult) {
    let dia = 3 + (width || 1) * 2;
    return roundDec(dia * mult, 3);
  }
  function seriesPointsShow(self, si) {
    let { scale, idxs } = self.series[0];
    let xData = self._data[0];
    let p0 = self.valToPos(xData[idxs[0]], scale, true);
    let p1 = self.valToPos(xData[idxs[1]], scale, true);
    let dim = abs(p1 - p0);
    let s = self.series[si];
    let maxPts = dim / (s.points.space * pxRatio);
    return idxs[1] - idxs[0] <= maxPts;
  }
  var facet = {
    scale: null,
    auto: true,
    sorted: 0,
    // internal caches
    min: inf,
    max: -inf
  };
  var gaps = (self, seriesIdx, idx0, idx1, nullGaps) => nullGaps;
  var xySeriesOpts = {
    show: true,
    auto: true,
    sorted: 0,
    gaps,
    alpha: 1,
    facets: [
      assign({}, facet, { scale: "x" }),
      assign({}, facet, { scale: "y" })
    ]
  };
  var ySeriesOpts = {
    scale: "y",
    auto: true,
    sorted: 0,
    show: true,
    spanGaps: false,
    gaps,
    alpha: 1,
    points: {
      show: seriesPointsShow,
      filter: null
      //  paths:
      //	stroke: "#000",
      //	fill: "#fff",
      //	width: 1,
      //	size: 10,
    },
    //	label: "Value",
    //	value: v => v,
    values: null,
    // internal caches
    min: inf,
    max: -inf,
    idxs: [],
    path: null,
    clip: null
  };
  function clampScale(self, val, scaleMin, scaleMax, scaleKey) {
    return scaleMin / 10;
  }
  var xScaleOpts = {
    time: FEAT_TIME,
    auto: true,
    distr: 1,
    log: 10,
    asinh: 1,
    min: null,
    max: null,
    dir: 1,
    ori: 0
  };
  var yScaleOpts = assign({}, xScaleOpts, {
    time: false,
    ori: 1
  });
  var syncs = {};
  function _sync(key, opts) {
    let s = syncs[key];
    if (!s) {
      s = {
        key,
        plots: [],
        sub(plot) {
          s.plots.push(plot);
        },
        unsub(plot) {
          s.plots = s.plots.filter((c) => c != plot);
        },
        pub(type, self, x, y, w, h, i) {
          for (let j = 0; j < s.plots.length; j++)
            s.plots[j] != self && s.plots[j].pub(type, self, x, y, w, h, i);
        }
      };
      if (key != null)
        syncs[key] = s;
    }
    return s;
  }
  var BAND_CLIP_FILL = 1 << 0;
  var BAND_CLIP_STROKE = 1 << 1;
  function orient(u, seriesIdx, cb) {
    const mode = u.mode;
    const series = u.series[seriesIdx];
    const data = mode == 2 ? u._data[seriesIdx] : u._data;
    const scales = u.scales;
    const bbox = u.bbox;
    let dx = data[0], dy = mode == 2 ? data[1] : data[seriesIdx], sx = mode == 2 ? scales[series.facets[0].scale] : scales[u.series[0].scale], sy = mode == 2 ? scales[series.facets[1].scale] : scales[series.scale], l = bbox.left, t = bbox.top, w = bbox.width, h = bbox.height, H = u.valToPosH, V = u.valToPosV;
    return sx.ori == 0 ? cb(
      series,
      dx,
      dy,
      sx,
      sy,
      H,
      V,
      l,
      t,
      w,
      h,
      moveToH,
      lineToH,
      rectH,
      arcH,
      bezierCurveToH
    ) : cb(
      series,
      dx,
      dy,
      sx,
      sy,
      V,
      H,
      t,
      l,
      h,
      w,
      moveToV,
      lineToV,
      rectV,
      arcV,
      bezierCurveToV
    );
  }
  function bandFillClipDirs(self, seriesIdx) {
    let fillDir = 0;
    let clipDirs = 0;
    let bands = ifNull(self.bands, EMPTY_ARR);
    for (let i = 0; i < bands.length; i++) {
      let b = bands[i];
      if (b.series[0] == seriesIdx)
        fillDir = b.dir;
      else if (b.series[1] == seriesIdx) {
        if (b.dir == 1)
          clipDirs |= 1;
        else
          clipDirs |= 2;
      }
    }
    return [
      fillDir,
      clipDirs == 1 ? -1 : (
        // neg only
        clipDirs == 2 ? 1 : (
          // pos only
          clipDirs == 3 ? 2 : (
            // both
            0
          )
        )
      )
    ];
  }
  function seriesFillTo(self, seriesIdx, dataMin, dataMax, bandFillDir) {
    let mode = self.mode;
    let series = self.series[seriesIdx];
    let scaleKey = mode == 2 ? series.facets[1].scale : series.scale;
    let scale = self.scales[scaleKey];
    return bandFillDir == -1 ? scale.min : bandFillDir == 1 ? scale.max : scale.distr == 3 ? scale.dir == 1 ? scale.min : scale.max : 0;
  }
  function clipBandLine(self, seriesIdx, idx0, idx1, strokePath, clipDir) {
    return orient(self, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
      let pxRound = series.pxRound;
      const dir = scaleX.dir * (scaleX.ori == 0 ? 1 : -1);
      const lineTo = scaleX.ori == 0 ? lineToH : lineToV;
      let frIdx, toIdx;
      if (dir == 1) {
        frIdx = idx0;
        toIdx = idx1;
      } else {
        frIdx = idx1;
        toIdx = idx0;
      }
      let x0 = pxRound(valToPosX(dataX[frIdx], scaleX, xDim, xOff));
      let y0 = pxRound(valToPosY(dataY[frIdx], scaleY, yDim, yOff));
      let x1 = pxRound(valToPosX(dataX[toIdx], scaleX, xDim, xOff));
      let yLimit = pxRound(valToPosY(clipDir == 1 ? scaleY.max : scaleY.min, scaleY, yDim, yOff));
      let clip = new Path2D(strokePath);
      lineTo(clip, x1, yLimit);
      lineTo(clip, x0, yLimit);
      lineTo(clip, x0, y0);
      return clip;
    });
  }
  function clipGaps(gaps2, ori, plotLft, plotTop, plotWid, plotHgt) {
    let clip = null;
    if (gaps2.length > 0) {
      clip = new Path2D();
      const rect2 = ori == 0 ? rectH : rectV;
      let prevGapEnd = plotLft;
      for (let i = 0; i < gaps2.length; i++) {
        let g = gaps2[i];
        if (g[1] > g[0]) {
          let w2 = g[0] - prevGapEnd;
          w2 > 0 && rect2(clip, prevGapEnd, plotTop, w2, plotTop + plotHgt);
          prevGapEnd = g[1];
        }
      }
      let w = plotLft + plotWid - prevGapEnd;
      let maxStrokeWidth = 10;
      w > 0 && rect2(clip, prevGapEnd, plotTop - maxStrokeWidth / 2, w, plotTop + plotHgt + maxStrokeWidth);
    }
    return clip;
  }
  function addGap(gaps2, fromX, toX) {
    let prevGap = gaps2[gaps2.length - 1];
    if (prevGap && prevGap[0] == fromX)
      prevGap[1] = toX;
    else
      gaps2.push([fromX, toX]);
  }
  function findGaps(xs, ys, idx0, idx1, dir, pixelForX, align) {
    let gaps2 = [];
    let len = xs.length;
    for (let i = dir == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += dir) {
      let yVal = ys[i];
      if (yVal === null) {
        let fr = i, to = i;
        if (dir == 1) {
          while (++i <= idx1 && ys[i] === null)
            to = i;
        } else {
          while (--i >= idx0 && ys[i] === null)
            to = i;
        }
        let frPx = pixelForX(xs[fr]);
        let toPx = to == fr ? frPx : pixelForX(xs[to]);
        let fri2 = fr - dir;
        let frPx2 = align <= 0 && fri2 >= 0 && fri2 < len ? pixelForX(xs[fri2]) : frPx;
        frPx = frPx2;
        let toi2 = to + dir;
        let toPx2 = align >= 0 && toi2 >= 0 && toi2 < len ? pixelForX(xs[toi2]) : toPx;
        toPx = toPx2;
        if (toPx >= frPx)
          gaps2.push([frPx, toPx]);
      }
    }
    return gaps2;
  }
  function pxRoundGen(pxAlign) {
    return pxAlign == 0 ? retArg0 : pxAlign == 1 ? round : (v) => incrRound(v, pxAlign);
  }
  function rect(ori) {
    let moveTo = ori == 0 ? moveToH : moveToV;
    let arcTo = ori == 0 ? (p, x1, y1, x2, y2, r2) => {
      p.arcTo(x1, y1, x2, y2, r2);
    } : (p, y1, x1, y2, x2, r2) => {
      p.arcTo(x1, y1, x2, y2, r2);
    };
    let rect2 = ori == 0 ? (p, x, y, w, h) => {
      p.rect(x, y, w, h);
    } : (p, y, x, h, w) => {
      p.rect(x, y, w, h);
    };
    return (p, x, y, w, h, endRad = 0, baseRad = 0) => {
      if (endRad == 0 && baseRad == 0)
        rect2(p, x, y, w, h);
      else {
        endRad = min(endRad, w / 2, h / 2);
        baseRad = min(baseRad, w / 2, h / 2);
        moveTo(p, x + endRad, y);
        arcTo(p, x + w, y, x + w, y + h, endRad);
        arcTo(p, x + w, y + h, x, y + h, baseRad);
        arcTo(p, x, y + h, x, y, baseRad);
        arcTo(p, x, y, x + w, y, endRad);
        p.closePath();
      }
    };
  }
  var moveToH = (p, x, y) => {
    p.moveTo(x, y);
  };
  var moveToV = (p, y, x) => {
    p.moveTo(x, y);
  };
  var lineToH = (p, x, y) => {
    p.lineTo(x, y);
  };
  var lineToV = (p, y, x) => {
    p.lineTo(x, y);
  };
  var rectH = rect(0);
  var rectV = rect(1);
  var arcH = (p, x, y, r2, startAngle, endAngle) => {
    p.arc(x, y, r2, startAngle, endAngle);
  };
  var arcV = (p, y, x, r2, startAngle, endAngle) => {
    p.arc(x, y, r2, startAngle, endAngle);
  };
  var bezierCurveToH = (p, bp1x, bp1y, bp2x, bp2y, p2x, p2y) => {
    p.bezierCurveTo(bp1x, bp1y, bp2x, bp2y, p2x, p2y);
  };
  var bezierCurveToV = (p, bp1y, bp1x, bp2y, bp2x, p2y, p2x) => {
    p.bezierCurveTo(bp1x, bp1y, bp2x, bp2y, p2x, p2y);
  };
  function points(opts) {
    return (u, seriesIdx, idx0, idx1, filtIdxs) => {
      return orient(u, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
        let { pxRound, points: points2 } = series;
        let moveTo, arc;
        if (scaleX.ori == 0) {
          moveTo = moveToH;
          arc = arcH;
        } else {
          moveTo = moveToV;
          arc = arcV;
        }
        const width = roundDec(points2.width * pxRatio, 3);
        let rad = (points2.size - points2.width) / 2 * pxRatio;
        let dia = roundDec(rad * 2, 3);
        let fill = new Path2D();
        let clip = new Path2D();
        let { left: lft, top, width: wid, height: hgt } = u.bbox;
        rectH(
          clip,
          lft - dia,
          top - dia,
          wid + dia * 2,
          hgt + dia * 2
        );
        const drawPoint = (pi) => {
          if (dataY[pi] != null) {
            let x = pxRound(valToPosX(dataX[pi], scaleX, xDim, xOff));
            let y = pxRound(valToPosY(dataY[pi], scaleY, yDim, yOff));
            moveTo(fill, x + rad, y);
            arc(fill, x, y, rad, 0, PI * 2);
          }
        };
        if (filtIdxs)
          filtIdxs.forEach(drawPoint);
        else {
          for (let pi = idx0; pi <= idx1; pi++)
            drawPoint(pi);
        }
        return {
          stroke: width > 0 ? fill : null,
          fill,
          clip,
          flags: BAND_CLIP_FILL | BAND_CLIP_STROKE
        };
      });
    };
  }
  function _drawAcc(lineTo) {
    return (stroke, accX, minY, maxY, inY, outY) => {
      if (minY != maxY) {
        if (inY != minY && outY != minY)
          lineTo(stroke, accX, minY);
        if (inY != maxY && outY != maxY)
          lineTo(stroke, accX, maxY);
        lineTo(stroke, accX, outY);
      }
    };
  }
  var drawAccH = _drawAcc(lineToH);
  var drawAccV = _drawAcc(lineToV);
  function linear(opts) {
    const alignGaps = ifNull(opts?.alignGaps, 0);
    return (u, seriesIdx, idx0, idx1) => {
      return orient(u, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
        [idx0, idx1] = nonNullIdxs(dataY, idx0, idx1);
        let pxRound = series.pxRound;
        let pixelForX = (val) => pxRound(valToPosX(val, scaleX, xDim, xOff));
        let pixelForY = (val) => pxRound(valToPosY(val, scaleY, yDim, yOff));
        let lineTo, drawAcc;
        if (scaleX.ori == 0) {
          lineTo = lineToH;
          drawAcc = drawAccH;
        } else {
          lineTo = lineToV;
          drawAcc = drawAccV;
        }
        const dir = scaleX.dir * (scaleX.ori == 0 ? 1 : -1);
        const _paths = { stroke: new Path2D(), fill: null, clip: null, band: null, gaps: null, flags: BAND_CLIP_FILL };
        const stroke = _paths.stroke;
        let hasGap = false;
        const decimate = idx1 - idx0 >= xDim * 4;
        if (decimate) {
          let xForPixel = (pos) => u.posToVal(pos, scaleX.key, true);
          let minY = null, maxY = null, inY, outY, drawnAtX;
          let accX = pixelForX(dataX[dir == 1 ? idx0 : idx1]);
          let idx0px = pixelForX(dataX[idx0]);
          let idx1px = pixelForX(dataX[idx1]);
          let nextAccXVal = xForPixel(dir == 1 ? idx0px + 1 : idx1px - 1);
          for (let i = dir == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += dir) {
            let xVal = dataX[i];
            let reuseAccX = dir == 1 ? xVal < nextAccXVal : xVal > nextAccXVal;
            let x = reuseAccX ? accX : pixelForX(xVal);
            let yVal = dataY[i];
            if (x == accX) {
              if (yVal != null) {
                outY = yVal;
                if (minY == null) {
                  lineTo(stroke, x, pixelForY(outY));
                  inY = minY = maxY = outY;
                } else {
                  if (outY < minY)
                    minY = outY;
                  else if (outY > maxY)
                    maxY = outY;
                }
              } else {
                if (yVal === null)
                  hasGap = true;
              }
            } else {
              if (minY != null)
                drawAcc(stroke, accX, pixelForY(minY), pixelForY(maxY), pixelForY(inY), pixelForY(outY));
              if (yVal != null) {
                outY = yVal;
                lineTo(stroke, x, pixelForY(outY));
                minY = maxY = inY = outY;
              } else {
                minY = maxY = null;
                if (yVal === null)
                  hasGap = true;
              }
              accX = x;
              nextAccXVal = xForPixel(accX + dir);
            }
          }
          if (minY != null && minY != maxY && drawnAtX != accX)
            drawAcc(stroke, accX, pixelForY(minY), pixelForY(maxY), pixelForY(inY), pixelForY(outY));
        } else {
          for (let i = dir == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += dir) {
            let yVal = dataY[i];
            if (yVal === null)
              hasGap = true;
            else if (yVal != null)
              lineTo(stroke, pixelForX(dataX[i]), pixelForY(yVal));
          }
        }
        let [bandFillDir, bandClipDir] = bandFillClipDirs(u, seriesIdx);
        if (series.fill != null || bandFillDir != 0) {
          let fill = _paths.fill = new Path2D(stroke);
          let fillToVal = series.fillTo(u, seriesIdx, series.min, series.max, bandFillDir);
          let fillToY = pixelForY(fillToVal);
          let frX = pixelForX(dataX[idx0]);
          let toX = pixelForX(dataX[idx1]);
          if (dir == -1)
            [toX, frX] = [frX, toX];
          lineTo(fill, toX, fillToY);
          lineTo(fill, frX, fillToY);
        }
        if (!series.spanGaps) {
          let gaps2 = [];
          hasGap && gaps2.push(...findGaps(dataX, dataY, idx0, idx1, dir, pixelForX, alignGaps));
          _paths.gaps = gaps2 = series.gaps(u, seriesIdx, idx0, idx1, gaps2);
          _paths.clip = clipGaps(gaps2, scaleX.ori, xOff, yOff, xDim, yDim);
        }
        if (bandClipDir != 0) {
          _paths.band = bandClipDir == 2 ? [
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, -1),
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, 1)
          ] : clipBandLine(u, seriesIdx, idx0, idx1, stroke, bandClipDir);
        }
        return _paths;
      });
    };
  }
  function stepped(opts) {
    const align = ifNull(opts.align, 1);
    const ascDesc = ifNull(opts.ascDesc, false);
    const alignGaps = ifNull(opts.alignGaps, 0);
    const extend = ifNull(opts.extend, false);
    return (u, seriesIdx, idx0, idx1) => {
      return orient(u, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
        [idx0, idx1] = nonNullIdxs(dataY, idx0, idx1);
        let pxRound = series.pxRound;
        let { left, width } = u.bbox;
        let pixelForX = (val) => pxRound(valToPosX(val, scaleX, xDim, xOff));
        let pixelForY = (val) => pxRound(valToPosY(val, scaleY, yDim, yOff));
        let lineTo = scaleX.ori == 0 ? lineToH : lineToV;
        const _paths = { stroke: new Path2D(), fill: null, clip: null, band: null, gaps: null, flags: BAND_CLIP_FILL };
        const stroke = _paths.stroke;
        const dir = scaleX.dir * (scaleX.ori == 0 ? 1 : -1);
        let prevYPos = pixelForY(dataY[dir == 1 ? idx0 : idx1]);
        let firstXPos = pixelForX(dataX[dir == 1 ? idx0 : idx1]);
        let prevXPos = firstXPos;
        let firstXPosExt = firstXPos;
        if (extend && align == -1) {
          firstXPosExt = left;
          lineTo(stroke, firstXPosExt, prevYPos);
        }
        lineTo(stroke, firstXPos, prevYPos);
        for (let i = dir == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += dir) {
          let yVal1 = dataY[i];
          if (yVal1 == null)
            continue;
          let x1 = pixelForX(dataX[i]);
          let y1 = pixelForY(yVal1);
          if (align == 1)
            lineTo(stroke, x1, prevYPos);
          else
            lineTo(stroke, prevXPos, y1);
          lineTo(stroke, x1, y1);
          prevYPos = y1;
          prevXPos = x1;
        }
        let prevXPosExt = prevXPos;
        if (extend && align == 1) {
          prevXPosExt = left + width;
          lineTo(stroke, prevXPosExt, prevYPos);
        }
        let [bandFillDir, bandClipDir] = bandFillClipDirs(u, seriesIdx);
        if (series.fill != null || bandFillDir != 0) {
          let fill = _paths.fill = new Path2D(stroke);
          let fillTo = series.fillTo(u, seriesIdx, series.min, series.max, bandFillDir);
          let fillToY = pixelForY(fillTo);
          lineTo(fill, prevXPosExt, fillToY);
          lineTo(fill, firstXPosExt, fillToY);
        }
        if (!series.spanGaps) {
          let gaps2 = [];
          gaps2.push(...findGaps(dataX, dataY, idx0, idx1, dir, pixelForX, alignGaps));
          let halfStroke = series.width * pxRatio / 2;
          let startsOffset = ascDesc || align == 1 ? halfStroke : -halfStroke;
          let endsOffset = ascDesc || align == -1 ? -halfStroke : halfStroke;
          gaps2.forEach((g) => {
            g[0] += startsOffset;
            g[1] += endsOffset;
          });
          _paths.gaps = gaps2 = series.gaps(u, seriesIdx, idx0, idx1, gaps2);
          _paths.clip = clipGaps(gaps2, scaleX.ori, xOff, yOff, xDim, yDim);
        }
        if (bandClipDir != 0) {
          _paths.band = bandClipDir == 2 ? [
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, -1),
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, 1)
          ] : clipBandLine(u, seriesIdx, idx0, idx1, stroke, bandClipDir);
        }
        return _paths;
      });
    };
  }
  function findColWidth(dataX, dataY, valToPosX, scaleX, xDim, xOff, colWid = inf) {
    if (dataX.length > 1) {
      let prevIdx = null;
      for (let i = 0, minDelta = Infinity; i < dataX.length; i++) {
        if (dataY[i] !== void 0) {
          if (prevIdx != null) {
            let delta = abs(dataX[i] - dataX[prevIdx]);
            if (delta < minDelta) {
              minDelta = delta;
              colWid = abs(valToPosX(dataX[i], scaleX, xDim, xOff) - valToPosX(dataX[prevIdx], scaleX, xDim, xOff));
            }
          }
          prevIdx = i;
        }
      }
    }
    return colWid;
  }
  function bars(opts) {
    opts = opts || EMPTY_OBJ;
    const size = ifNull(opts.size, [0.6, inf, 1]);
    const align = opts.align || 0;
    const _extraGap = opts.gap || 0;
    let ro = opts.radius;
    ro = // [valueRadius, baselineRadius]
    ro == null ? [0, 0] : typeof ro == "number" ? [ro, 0] : ro;
    const radiusFn = fnOrSelf(ro);
    const gapFactor = 1 - size[0];
    const _maxWidth = ifNull(size[1], inf);
    const _minWidth = ifNull(size[2], 1);
    const disp = ifNull(opts.disp, EMPTY_OBJ);
    const _each = ifNull(opts.each, (_2) => {
    });
    const { fill: dispFills, stroke: dispStrokes } = disp;
    return (u, seriesIdx, idx0, idx1) => {
      return orient(u, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
        let pxRound = series.pxRound;
        let _align = align;
        let extraGap = _extraGap * pxRatio;
        let maxWidth = _maxWidth * pxRatio;
        let minWidth = _minWidth * pxRatio;
        let valRadius, baseRadius;
        if (scaleX.ori == 0)
          [valRadius, baseRadius] = radiusFn(u, seriesIdx);
        else
          [baseRadius, valRadius] = radiusFn(u, seriesIdx);
        const _dirX = scaleX.dir * (scaleX.ori == 0 ? 1 : -1);
        let rect2 = scaleX.ori == 0 ? rectH : rectV;
        let each = scaleX.ori == 0 ? _each : (u2, seriesIdx2, i, top, lft, hgt, wid) => {
          _each(u2, seriesIdx2, i, lft, top, wid, hgt);
        };
        let band = ifNull(u.bands, EMPTY_ARR).find((b) => b.series[0] == seriesIdx);
        let fillDir = band != null ? band.dir : 0;
        let fillTo = series.fillTo(u, seriesIdx, series.min, series.max, fillDir);
        let fillToY = pxRound(valToPosY(fillTo, scaleY, yDim, yOff));
        let xShift, barWid, fullGap, colWid = xDim;
        let strokeWidth = pxRound(series.width * pxRatio);
        let multiPath = false;
        let fillColors = null;
        let fillPaths = null;
        let strokeColors = null;
        let strokePaths = null;
        if (dispFills != null && (strokeWidth == 0 || dispStrokes != null)) {
          multiPath = true;
          fillColors = dispFills.values(u, seriesIdx, idx0, idx1);
          fillPaths = /* @__PURE__ */ new Map();
          new Set(fillColors).forEach((color) => {
            if (color != null)
              fillPaths.set(color, new Path2D());
          });
          if (strokeWidth > 0) {
            strokeColors = dispStrokes.values(u, seriesIdx, idx0, idx1);
            strokePaths = /* @__PURE__ */ new Map();
            new Set(strokeColors).forEach((color) => {
              if (color != null)
                strokePaths.set(color, new Path2D());
            });
          }
        }
        let { x0, size: size2 } = disp;
        if (x0 != null && size2 != null) {
          _align = 1;
          dataX = x0.values(u, seriesIdx, idx0, idx1);
          if (x0.unit == 2)
            dataX = dataX.map((pct) => u.posToVal(xOff + pct * xDim, scaleX.key, true));
          let sizes = size2.values(u, seriesIdx, idx0, idx1);
          if (size2.unit == 2)
            barWid = sizes[0] * xDim;
          else
            barWid = valToPosX(sizes[0], scaleX, xDim, xOff) - valToPosX(0, scaleX, xDim, xOff);
          colWid = findColWidth(dataX, dataY, valToPosX, scaleX, xDim, xOff, colWid);
          let gapWid = colWid - barWid;
          fullGap = gapWid + extraGap;
        } else {
          colWid = findColWidth(dataX, dataY, valToPosX, scaleX, xDim, xOff, colWid);
          let gapWid = colWid * gapFactor;
          fullGap = gapWid + extraGap;
          barWid = colWid - fullGap;
        }
        if (fullGap < 1)
          fullGap = 0;
        if (strokeWidth >= barWid / 2)
          strokeWidth = 0;
        if (fullGap < 5)
          pxRound = retArg0;
        let insetStroke = fullGap > 0;
        let rawBarWid = colWid - fullGap - (insetStroke ? strokeWidth : 0);
        barWid = pxRound(clamp(rawBarWid, minWidth, maxWidth));
        xShift = (_align == 0 ? barWid / 2 : _align == _dirX ? 0 : barWid) - _align * _dirX * ((_align == 0 ? extraGap / 2 : 0) + (insetStroke ? strokeWidth / 2 : 0));
        const _paths = { stroke: null, fill: null, clip: null, band: null, gaps: null, flags: 0 };
        const stroke = multiPath ? null : new Path2D();
        let dataY0 = null;
        if (band != null)
          dataY0 = u.data[band.series[1]];
        else {
          let { y0, y1 } = disp;
          if (y0 != null && y1 != null) {
            dataY = y1.values(u, seriesIdx, idx0, idx1);
            dataY0 = y0.values(u, seriesIdx, idx0, idx1);
          }
        }
        let radVal = valRadius * barWid;
        let radBase = baseRadius * barWid;
        for (let i = _dirX == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += _dirX) {
          let yVal = dataY[i];
          if (yVal == null)
            continue;
          if (dataY0 != null) {
            let yVal0 = dataY0[i] ?? 0;
            if (yVal - yVal0 == 0)
              continue;
            fillToY = valToPosY(yVal0, scaleY, yDim, yOff);
          }
          let xVal = scaleX.distr != 2 || disp != null ? dataX[i] : i;
          let xPos = valToPosX(xVal, scaleX, xDim, xOff);
          let yPos = valToPosY(ifNull(yVal, fillTo), scaleY, yDim, yOff);
          let lft = pxRound(xPos - xShift);
          let btm = pxRound(max(yPos, fillToY));
          let top = pxRound(min(yPos, fillToY));
          let barHgt = btm - top;
          if (yVal != null) {
            let rv = yVal < 0 ? radBase : radVal;
            let rb = yVal < 0 ? radVal : radBase;
            if (multiPath) {
              if (strokeWidth > 0 && strokeColors[i] != null)
                rect2(strokePaths.get(strokeColors[i]), lft, top + floor(strokeWidth / 2), barWid, max(0, barHgt - strokeWidth), rv, rb);
              if (fillColors[i] != null)
                rect2(fillPaths.get(fillColors[i]), lft, top + floor(strokeWidth / 2), barWid, max(0, barHgt - strokeWidth), rv, rb);
            } else
              rect2(stroke, lft, top + floor(strokeWidth / 2), barWid, max(0, barHgt - strokeWidth), rv, rb);
            each(
              u,
              seriesIdx,
              i,
              lft - strokeWidth / 2,
              top,
              barWid + strokeWidth,
              barHgt
            );
          }
        }
        if (strokeWidth > 0)
          _paths.stroke = multiPath ? strokePaths : stroke;
        else if (!multiPath) {
          _paths._fill = series.width == 0 ? series._fill : series._stroke ?? series._fill;
          _paths.width = 0;
        }
        _paths.fill = multiPath ? fillPaths : stroke;
        return _paths;
      });
    };
  }
  function splineInterp(interp, opts) {
    const alignGaps = ifNull(opts?.alignGaps, 0);
    return (u, seriesIdx, idx0, idx1) => {
      return orient(u, seriesIdx, (series, dataX, dataY, scaleX, scaleY, valToPosX, valToPosY, xOff, yOff, xDim, yDim) => {
        [idx0, idx1] = nonNullIdxs(dataY, idx0, idx1);
        let pxRound = series.pxRound;
        let pixelForX = (val) => pxRound(valToPosX(val, scaleX, xDim, xOff));
        let pixelForY = (val) => pxRound(valToPosY(val, scaleY, yDim, yOff));
        let moveTo, bezierCurveTo, lineTo;
        if (scaleX.ori == 0) {
          moveTo = moveToH;
          lineTo = lineToH;
          bezierCurveTo = bezierCurveToH;
        } else {
          moveTo = moveToV;
          lineTo = lineToV;
          bezierCurveTo = bezierCurveToV;
        }
        const dir = scaleX.dir * (scaleX.ori == 0 ? 1 : -1);
        let firstXPos = pixelForX(dataX[dir == 1 ? idx0 : idx1]);
        let prevXPos = firstXPos;
        let xCoords = [];
        let yCoords = [];
        for (let i = dir == 1 ? idx0 : idx1; i >= idx0 && i <= idx1; i += dir) {
          let yVal = dataY[i];
          if (yVal != null) {
            let xVal = dataX[i];
            let xPos = pixelForX(xVal);
            xCoords.push(prevXPos = xPos);
            yCoords.push(pixelForY(dataY[i]));
          }
        }
        const _paths = { stroke: interp(xCoords, yCoords, moveTo, lineTo, bezierCurveTo, pxRound), fill: null, clip: null, band: null, gaps: null, flags: BAND_CLIP_FILL };
        const stroke = _paths.stroke;
        let [bandFillDir, bandClipDir] = bandFillClipDirs(u, seriesIdx);
        if (series.fill != null || bandFillDir != 0) {
          let fill = _paths.fill = new Path2D(stroke);
          let fillTo = series.fillTo(u, seriesIdx, series.min, series.max, bandFillDir);
          let fillToY = pixelForY(fillTo);
          lineTo(fill, prevXPos, fillToY);
          lineTo(fill, firstXPos, fillToY);
        }
        if (!series.spanGaps) {
          let gaps2 = [];
          gaps2.push(...findGaps(dataX, dataY, idx0, idx1, dir, pixelForX, alignGaps));
          _paths.gaps = gaps2 = series.gaps(u, seriesIdx, idx0, idx1, gaps2);
          _paths.clip = clipGaps(gaps2, scaleX.ori, xOff, yOff, xDim, yDim);
        }
        if (bandClipDir != 0) {
          _paths.band = bandClipDir == 2 ? [
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, -1),
            clipBandLine(u, seriesIdx, idx0, idx1, stroke, 1)
          ] : clipBandLine(u, seriesIdx, idx0, idx1, stroke, bandClipDir);
        }
        return _paths;
      });
    };
  }
  function monotoneCubic(opts) {
    return splineInterp(_monotoneCubic, opts);
  }
  function _monotoneCubic(xs, ys, moveTo, lineTo, bezierCurveTo, pxRound) {
    const n = xs.length;
    if (n < 2)
      return null;
    const path = new Path2D();
    moveTo(path, xs[0], ys[0]);
    if (n == 2)
      lineTo(path, xs[1], ys[1]);
    else {
      let ms = Array(n), ds = Array(n - 1), dys = Array(n - 1), dxs = Array(n - 1);
      for (let i = 0; i < n - 1; i++) {
        dys[i] = ys[i + 1] - ys[i];
        dxs[i] = xs[i + 1] - xs[i];
        ds[i] = dys[i] / dxs[i];
      }
      ms[0] = ds[0];
      for (let i = 1; i < n - 1; i++) {
        if (ds[i] === 0 || ds[i - 1] === 0 || ds[i - 1] > 0 !== ds[i] > 0)
          ms[i] = 0;
        else {
          ms[i] = 3 * (dxs[i - 1] + dxs[i]) / ((2 * dxs[i] + dxs[i - 1]) / ds[i - 1] + (dxs[i] + 2 * dxs[i - 1]) / ds[i]);
          if (!isFinite(ms[i]))
            ms[i] = 0;
        }
      }
      ms[n - 1] = ds[n - 2];
      for (let i = 0; i < n - 1; i++) {
        bezierCurveTo(
          path,
          xs[i] + dxs[i] / 3,
          ys[i] + ms[i] * dxs[i] / 3,
          xs[i + 1] - dxs[i] / 3,
          ys[i + 1] - ms[i + 1] * dxs[i] / 3,
          xs[i + 1],
          ys[i + 1]
        );
      }
    }
    return path;
  }
  var cursorPlots = /* @__PURE__ */ new Set();
  function invalidateRects() {
    for (let u of cursorPlots)
      u.syncRect(true);
  }
  if (domEnv) {
    on(resize, win, invalidateRects);
    on(scroll, win, invalidateRects, true);
    on(dppxchange, win, () => {
      uPlot.pxRatio = pxRatio;
    });
  }
  var linearPath = linear();
  var pointsPath = points();
  function setDefaults(d, xo, yo, initY) {
    let d2 = initY ? [d[0], d[1]].concat(d.slice(2)) : [d[0]].concat(d.slice(1));
    return d2.map((o, i) => setDefault(o, i, xo, yo));
  }
  function setDefaults2(d, xyo) {
    return d.map((o, i) => i == 0 ? {} : assign({}, xyo, o));
  }
  function setDefault(o, i, xo, yo) {
    return assign({}, i == 0 ? xo : yo, o);
  }
  function snapNumX(self, dataMin, dataMax) {
    return dataMin == null ? nullNullTuple : [dataMin, dataMax];
  }
  var snapTimeX = snapNumX;
  function snapNumY(self, dataMin, dataMax) {
    return dataMin == null ? nullNullTuple : rangeNum(dataMin, dataMax, rangePad, true);
  }
  function snapLogY(self, dataMin, dataMax, scale) {
    return dataMin == null ? nullNullTuple : rangeLog(dataMin, dataMax, self.scales[scale].log, false);
  }
  var snapLogX = snapLogY;
  function snapAsinhY(self, dataMin, dataMax, scale) {
    return dataMin == null ? nullNullTuple : rangeAsinh(dataMin, dataMax, self.scales[scale].log, false);
  }
  var snapAsinhX = snapAsinhY;
  function findIncr(minVal, maxVal, incrs, dim, minSpace) {
    let intDigits = max(numIntDigits(minVal), numIntDigits(maxVal));
    let delta = maxVal - minVal;
    let incrIdx = closestIdx(minSpace / dim * delta, incrs);
    do {
      let foundIncr = incrs[incrIdx];
      let foundSpace = dim * foundIncr / delta;
      if (foundSpace >= minSpace && intDigits + (foundIncr < 5 ? fixedDec.get(foundIncr) : 0) <= 17)
        return [foundIncr, foundSpace];
    } while (++incrIdx < incrs.length);
    return [0, 0];
  }
  function pxRatioFont(font2) {
    let fontSize, fontSizeCss;
    font2 = font2.replace(/(\d+)px/, (m, p1) => (fontSize = round((fontSizeCss = +p1) * pxRatio)) + "px");
    return [font2, fontSize, fontSizeCss];
  }
  function syncFontSize(axis) {
    if (axis.show) {
      [axis.font, axis.labelFont].forEach((f) => {
        let size = roundDec(f[2] * pxRatio, 1);
        f[0] = f[0].replace(/[0-9.]+px/, size + "px");
        f[1] = size;
      });
    }
  }
  function uPlot(opts, data, then) {
    const self = {
      mode: ifNull(opts.mode, 1)
    };
    const mode = self.mode;
    function getHPos(val, scale, dim, off2) {
      let pct = scale.valToPct(val);
      return off2 + dim * (scale.dir == -1 ? 1 - pct : pct);
    }
    function getVPos(val, scale, dim, off2) {
      let pct = scale.valToPct(val);
      return off2 + dim * (scale.dir == -1 ? pct : 1 - pct);
    }
    function getPos(val, scale, dim, off2) {
      return scale.ori == 0 ? getHPos(val, scale, dim, off2) : getVPos(val, scale, dim, off2);
    }
    self.valToPosH = getHPos;
    self.valToPosV = getVPos;
    let ready = false;
    self.status = 0;
    const root = self.root = placeDiv(UPLOT);
    if (opts.id != null)
      root.id = opts.id;
    addClass(root, opts.class);
    if (opts.title) {
      let title = placeDiv(TITLE, root);
      title.textContent = opts.title;
    }
    const can = placeTag("canvas");
    const ctx = self.ctx = can.getContext("2d");
    const wrap = placeDiv(WRAP, root);
    on("click", wrap, (e) => {
      if (e.target === over) {
        let didDrag = mouseLeft1 != mouseLeft0 || mouseTop1 != mouseTop0;
        didDrag && drag.click(self, e);
      }
    }, true);
    const under = self.under = placeDiv(UNDER, wrap);
    wrap.appendChild(can);
    const over = self.over = placeDiv(OVER, wrap);
    opts = copy(opts);
    const pxAlign = +ifNull(opts.pxAlign, 1);
    const pxRound = pxRoundGen(pxAlign);
    (opts.plugins || []).forEach((p) => {
      if (p.opts)
        opts = p.opts(self, opts) || opts;
    });
    const ms = opts.ms || 1e-3;
    const series = self.series = mode == 1 ? setDefaults(opts.series || [], xSeriesOpts, ySeriesOpts, false) : setDefaults2(opts.series || [null], xySeriesOpts);
    const axes = self.axes = setDefaults(opts.axes || [], xAxisOpts, yAxisOpts, true);
    const scales = self.scales = {};
    const bands = self.bands = opts.bands || [];
    bands.forEach((b) => {
      b.fill = fnOrSelf(b.fill || null);
      b.dir = ifNull(b.dir, -1);
    });
    const xScaleKey = mode == 2 ? series[1].facets[0].scale : series[0].scale;
    const drawOrderMap = {
      axes: drawAxesGrid,
      series: drawSeries
    };
    const drawOrder = (opts.drawOrder || ["axes", "series"]).map((key2) => drawOrderMap[key2]);
    function initValToPct(sc) {
      const getVal = sc.distr == 3 ? (val) => log10(val > 0 ? val : sc.clamp(self, val, sc.min, sc.max, sc.key)) : sc.distr == 4 ? (val) => asinh(val, sc.asinh) : sc.distr == 100 ? (val) => sc.fwd(val) : (val) => val;
      return (val) => {
        let _val = getVal(val);
        let { _min, _max } = sc;
        let delta = _max - _min;
        return (_val - _min) / delta;
      };
    }
    function initScale(scaleKey) {
      let sc = scales[scaleKey];
      if (sc == null) {
        let scaleOpts = (opts.scales || EMPTY_OBJ)[scaleKey] || EMPTY_OBJ;
        if (scaleOpts.from != null) {
          initScale(scaleOpts.from);
          let sc2 = assign({}, scales[scaleOpts.from], scaleOpts, { key: scaleKey });
          sc2.valToPct = initValToPct(sc2);
          scales[scaleKey] = sc2;
        } else {
          sc = scales[scaleKey] = assign({}, scaleKey == xScaleKey ? xScaleOpts : yScaleOpts, scaleOpts);
          sc.key = scaleKey;
          let isTime = sc.time;
          let rn = sc.range;
          let rangeIsArr = isArr(rn);
          if (scaleKey != xScaleKey || mode == 2 && !isTime) {
            if (rangeIsArr && (rn[0] == null || rn[1] == null)) {
              rn = {
                min: rn[0] == null ? autoRangePart : {
                  mode: 1,
                  hard: rn[0],
                  soft: rn[0]
                },
                max: rn[1] == null ? autoRangePart : {
                  mode: 1,
                  hard: rn[1],
                  soft: rn[1]
                }
              };
              rangeIsArr = false;
            }
            if (!rangeIsArr && isObj(rn)) {
              let cfg = rn;
              rn = (self2, dataMin, dataMax) => dataMin == null ? nullNullTuple : rangeNum(dataMin, dataMax, cfg);
            }
          }
          sc.range = fnOrSelf(rn || (isTime ? snapTimeX : scaleKey == xScaleKey ? sc.distr == 3 ? snapLogX : sc.distr == 4 ? snapAsinhX : snapNumX : sc.distr == 3 ? snapLogY : sc.distr == 4 ? snapAsinhY : snapNumY));
          sc.auto = fnOrSelf(rangeIsArr ? false : sc.auto);
          sc.clamp = fnOrSelf(sc.clamp || clampScale);
          sc._min = sc._max = null;
          sc.valToPct = initValToPct(sc);
        }
      }
    }
    initScale("x");
    initScale("y");
    if (mode == 1) {
      series.forEach((s) => {
        initScale(s.scale);
      });
    }
    axes.forEach((a) => {
      initScale(a.scale);
    });
    for (let k in opts.scales)
      initScale(k);
    const scaleX = scales[xScaleKey];
    const xScaleDistr = scaleX.distr;
    let valToPosX, valToPosY;
    if (scaleX.ori == 0) {
      addClass(root, ORI_HZ);
      valToPosX = getHPos;
      valToPosY = getVPos;
    } else {
      addClass(root, ORI_VT);
      valToPosX = getVPos;
      valToPosY = getHPos;
    }
    const pendScales = {};
    for (let k in scales) {
      let sc = scales[k];
      if (sc.min != null || sc.max != null) {
        pendScales[k] = { min: sc.min, max: sc.max };
        sc.min = sc.max = null;
      }
    }
    const _tzDate = opts.tzDate || ((ts) => new Date(round(ts / ms)));
    const _fmtDate = opts.fmtDate || fmtDate;
    const _timeAxisSplits = ms == 1 ? timeAxisSplitsMs(_tzDate) : timeAxisSplitsS(_tzDate);
    const _timeAxisVals = timeAxisVals(_tzDate, timeAxisStamps(ms == 1 ? _timeAxisStampsMs : _timeAxisStampsS, _fmtDate));
    const _timeSeriesVal = timeSeriesVal(_tzDate, timeSeriesStamp(_timeSeriesStamp, _fmtDate));
    const activeIdxs = [];
    const legend = self.legend = assign({}, legendOpts, opts.legend);
    const cursor = self.cursor = assign({}, cursorOpts, { drag: { y: mode == 2 } }, opts.cursor);
    const showLegend = legend.show;
    const showCursor = cursor.show;
    const markers = legend.markers;
    {
      legend.idxs = activeIdxs;
      markers.width = fnOrSelf(markers.width);
      markers.dash = fnOrSelf(markers.dash);
      markers.stroke = fnOrSelf(markers.stroke);
      markers.fill = fnOrSelf(markers.fill);
    }
    let legendTable;
    let legendHead;
    let legendBody;
    let legendRows = [];
    let legendCells = [];
    let legendCols;
    let multiValLegend = false;
    let NULL_LEGEND_VALUES = {};
    if (legend.live) {
      const getMultiVals = series[1] ? series[1].values : null;
      multiValLegend = getMultiVals != null;
      legendCols = multiValLegend ? getMultiVals(self, 1, 0) : { _: 0 };
      for (let k in legendCols)
        NULL_LEGEND_VALUES[k] = LEGEND_DISP;
    }
    if (showLegend) {
      legendTable = placeTag("table", LEGEND, root);
      legendBody = placeTag("tbody", null, legendTable);
      legend.mount(self, legendTable);
      if (multiValLegend) {
        legendHead = placeTag("thead", null, legendTable, legendBody);
        let head = placeTag("tr", null, legendHead);
        placeTag("th", null, head);
        for (var key in legendCols)
          placeTag("th", LEGEND_LABEL, head).textContent = key;
      } else {
        addClass(legendTable, LEGEND_INLINE);
        legend.live && addClass(legendTable, LEGEND_LIVE);
      }
    }
    const son = { show: true };
    const soff = { show: false };
    function initLegendRow(s, i) {
      if (i == 0 && (multiValLegend || !legend.live || mode == 2))
        return nullNullTuple;
      let cells = [];
      let row = placeTag("tr", LEGEND_SERIES, legendBody, legendBody.childNodes[i]);
      addClass(row, s.class);
      if (!s.show)
        addClass(row, OFF);
      let label = placeTag("th", null, row);
      if (markers.show) {
        let indic = placeDiv(LEGEND_MARKER, label);
        if (i > 0) {
          let width = markers.width(self, i);
          if (width)
            indic.style.border = width + "px " + markers.dash(self, i) + " " + markers.stroke(self, i);
          indic.style.background = markers.fill(self, i);
        }
      }
      let text = placeDiv(LEGEND_LABEL, label);
      if (s.label instanceof HTMLElement)
        text.appendChild(s.label);
      else
        text.textContent = s.label;
      if (i > 0) {
        if (!markers.show)
          text.style.color = s.width > 0 ? markers.stroke(self, i) : markers.fill(self, i);
        onMouse("click", label, (e) => {
          if (cursor._lock)
            return;
          setCursorEvent(e);
          let seriesIdx = series.indexOf(s);
          if ((e.ctrlKey || e.metaKey) != legend.isolate) {
            let isolate = series.some((s2, i2) => i2 > 0 && i2 != seriesIdx && s2.show);
            series.forEach((s2, i2) => {
              i2 > 0 && setSeries(i2, isolate ? i2 == seriesIdx ? son : soff : son, true, syncOpts.setSeries);
            });
          } else
            setSeries(seriesIdx, { show: !s.show }, true, syncOpts.setSeries);
        }, false);
        if (cursorFocus) {
          onMouse(mouseenter, label, (e) => {
            if (cursor._lock)
              return;
            setCursorEvent(e);
            setSeries(series.indexOf(s), FOCUS_TRUE, true, syncOpts.setSeries);
          }, false);
        }
      }
      for (var key2 in legendCols) {
        let v = placeTag("td", LEGEND_VALUE, row);
        v.textContent = "--";
        cells.push(v);
      }
      return [row, cells];
    }
    const mouseListeners = /* @__PURE__ */ new Map();
    function onMouse(ev, targ, fn, onlyTarg = true) {
      const targListeners = mouseListeners.get(targ) || {};
      const listener = cursor.bind[ev](self, targ, fn, onlyTarg);
      if (listener) {
        on(ev, targ, targListeners[ev] = listener);
        mouseListeners.set(targ, targListeners);
      }
    }
    function offMouse(ev, targ, fn) {
      const targListeners = mouseListeners.get(targ) || {};
      for (let k in targListeners) {
        if (ev == null || k == ev) {
          off(k, targ, targListeners[k]);
          delete targListeners[k];
        }
      }
      if (ev == null)
        mouseListeners.delete(targ);
    }
    let fullWidCss = 0;
    let fullHgtCss = 0;
    let plotWidCss = 0;
    let plotHgtCss = 0;
    let plotLftCss = 0;
    let plotTopCss = 0;
    let _plotLftCss = plotLftCss;
    let _plotTopCss = plotTopCss;
    let _plotWidCss = plotWidCss;
    let _plotHgtCss = plotHgtCss;
    let plotLft = 0;
    let plotTop = 0;
    let plotWid = 0;
    let plotHgt = 0;
    self.bbox = {};
    let shouldSetScales = false;
    let shouldSetSize = false;
    let shouldConvergeSize = false;
    let shouldSetCursor = false;
    let shouldSetSelect = false;
    let shouldSetLegend = false;
    function _setSize(width, height, force) {
      if (force || (width != self.width || height != self.height))
        calcSize(width, height);
      resetYSeries(false);
      shouldConvergeSize = true;
      shouldSetSize = true;
      commit();
    }
    function calcSize(width, height) {
      self.width = fullWidCss = plotWidCss = width;
      self.height = fullHgtCss = plotHgtCss = height;
      plotLftCss = plotTopCss = 0;
      calcPlotRect();
      calcAxesRects();
      let bb = self.bbox;
      plotLft = bb.left = incrRound(plotLftCss * pxRatio, 0.5);
      plotTop = bb.top = incrRound(plotTopCss * pxRatio, 0.5);
      plotWid = bb.width = incrRound(plotWidCss * pxRatio, 0.5);
      plotHgt = bb.height = incrRound(plotHgtCss * pxRatio, 0.5);
    }
    const CYCLE_LIMIT = 3;
    function convergeSize() {
      let converged = false;
      let cycleNum = 0;
      while (!converged) {
        cycleNum++;
        let axesConverged = axesCalc(cycleNum);
        let paddingConverged = paddingCalc(cycleNum);
        converged = cycleNum == CYCLE_LIMIT || axesConverged && paddingConverged;
        if (!converged) {
          calcSize(self.width, self.height);
          shouldSetSize = true;
        }
      }
    }
    function setSize({ width, height }) {
      _setSize(width, height);
    }
    self.setSize = setSize;
    function calcPlotRect() {
      let hasTopAxis = false;
      let hasBtmAxis = false;
      let hasRgtAxis = false;
      let hasLftAxis = false;
      axes.forEach((axis, i) => {
        if (axis.show && axis._show) {
          let { side, _size } = axis;
          let isVt = side % 2;
          let labelSize = axis.label != null ? axis.labelSize : 0;
          let fullSize = _size + labelSize;
          if (fullSize > 0) {
            if (isVt) {
              plotWidCss -= fullSize;
              if (side == 3) {
                plotLftCss += fullSize;
                hasLftAxis = true;
              } else
                hasRgtAxis = true;
            } else {
              plotHgtCss -= fullSize;
              if (side == 0) {
                plotTopCss += fullSize;
                hasTopAxis = true;
              } else
                hasBtmAxis = true;
            }
          }
        }
      });
      sidesWithAxes[0] = hasTopAxis;
      sidesWithAxes[1] = hasRgtAxis;
      sidesWithAxes[2] = hasBtmAxis;
      sidesWithAxes[3] = hasLftAxis;
      plotWidCss -= _padding[1] + _padding[3];
      plotLftCss += _padding[3];
      plotHgtCss -= _padding[2] + _padding[0];
      plotTopCss += _padding[0];
    }
    function calcAxesRects() {
      let off1 = plotLftCss + plotWidCss;
      let off2 = plotTopCss + plotHgtCss;
      let off3 = plotLftCss;
      let off0 = plotTopCss;
      function incrOffset(side, size) {
        switch (side) {
          case 1:
            off1 += size;
            return off1 - size;
          case 2:
            off2 += size;
            return off2 - size;
          case 3:
            off3 -= size;
            return off3 + size;
          case 0:
            off0 -= size;
            return off0 + size;
        }
      }
      axes.forEach((axis, i) => {
        if (axis.show && axis._show) {
          let side = axis.side;
          axis._pos = incrOffset(side, axis._size);
          if (axis.label != null)
            axis._lpos = incrOffset(side, axis.labelSize);
        }
      });
    }
    if (cursor.dataIdx == null) {
      let hov = cursor.hover;
      let skip = hov.skip = new Set(hov.skip ?? []);
      skip.add(void 0);
      let prox = hov.prox = fnOrSelf(hov.prox);
      let bias = hov.bias ?? (hov.bias = 0);
      cursor.dataIdx = (self2, seriesIdx, cursorIdx, valAtPosX) => {
        if (seriesIdx == 0)
          return cursorIdx;
        let idx2 = cursorIdx;
        let _prox = prox(self2, seriesIdx, cursorIdx, valAtPosX) ?? inf;
        let withProx = _prox >= 0 && _prox < inf;
        let xDim = scaleX.ori == 0 ? plotWidCss : plotHgtCss;
        let cursorLft = cursor.left;
        let xValues = data[0];
        let yValues = data[seriesIdx];
        if (skip.has(yValues[cursorIdx])) {
          idx2 = null;
          let nonNullLft = null, nonNullRgt = null, j;
          if (bias == 0 || bias == -1) {
            j = cursorIdx;
            while (nonNullLft == null && j-- > 0) {
              if (!skip.has(yValues[j]))
                nonNullLft = j;
            }
          }
          if (bias == 0 || bias == 1) {
            j = cursorIdx;
            while (nonNullRgt == null && j++ < yValues.length) {
              if (!skip.has(yValues[j]))
                nonNullRgt = j;
            }
          }
          if (nonNullLft != null || nonNullRgt != null) {
            if (withProx) {
              let lftPos = nonNullLft == null ? -Infinity : valToPosX(xValues[nonNullLft], scaleX, xDim, 0);
              let rgtPos = nonNullRgt == null ? Infinity : valToPosX(xValues[nonNullRgt], scaleX, xDim, 0);
              let lftDelta = cursorLft - lftPos;
              let rgtDelta = rgtPos - cursorLft;
              if (lftDelta <= rgtDelta) {
                if (lftDelta <= _prox)
                  idx2 = nonNullLft;
              } else {
                if (rgtDelta <= _prox)
                  idx2 = nonNullRgt;
              }
            } else {
              idx2 = nonNullRgt == null ? nonNullLft : nonNullLft == null ? nonNullRgt : cursorIdx - nonNullLft <= nonNullRgt - cursorIdx ? nonNullLft : nonNullRgt;
            }
          }
        } else if (withProx) {
          let dist = abs(cursorLft - valToPosX(xValues[cursorIdx], scaleX, xDim, 0));
          if (dist > _prox)
            idx2 = null;
        }
        return idx2;
      };
    }
    const setCursorEvent = (e) => {
      cursor.event = e;
    };
    cursor.idxs = activeIdxs;
    cursor._lock = false;
    let points2 = cursor.points;
    points2.show = fnOrSelf(points2.show);
    points2.size = fnOrSelf(points2.size);
    points2.stroke = fnOrSelf(points2.stroke);
    points2.width = fnOrSelf(points2.width);
    points2.fill = fnOrSelf(points2.fill);
    const focus = self.focus = assign({}, opts.focus || { alpha: 0.3 }, cursor.focus);
    const cursorFocus = focus.prox >= 0;
    const cursorOnePt = cursorFocus && points2.one;
    let cursorPts = [];
    let cursorPtsLft = [];
    let cursorPtsTop = [];
    function initCursorPt(s, si) {
      let pt = points2.show(self, si);
      if (pt instanceof HTMLElement) {
        addClass(pt, CURSOR_PT);
        addClass(pt, s.class);
        elTrans(pt, -10, -10, plotWidCss, plotHgtCss);
        over.insertBefore(pt, cursorPts[si]);
        return pt;
      }
    }
    function initSeries(s, i) {
      if (mode == 1 || i > 0) {
        let isTime = mode == 1 && scales[s.scale].time;
        let sv = s.value;
        s.value = isTime ? isStr(sv) ? timeSeriesVal(_tzDate, timeSeriesStamp(sv, _fmtDate)) : sv || _timeSeriesVal : sv || numSeriesVal;
        s.label = s.label || (isTime ? timeSeriesLabel : numSeriesLabel);
      }
      if (cursorOnePt || i > 0) {
        s.width = s.width == null ? 1 : s.width;
        s.paths = s.paths || linearPath || retNull;
        s.fillTo = fnOrSelf(s.fillTo || seriesFillTo);
        s.pxAlign = +ifNull(s.pxAlign, pxAlign);
        s.pxRound = pxRoundGen(s.pxAlign);
        s.stroke = fnOrSelf(s.stroke || null);
        s.fill = fnOrSelf(s.fill || null);
        s._stroke = s._fill = s._paths = s._focus = null;
        let _ptDia = ptDia(max(1, s.width), 1);
        let points3 = s.points = assign({}, {
          size: _ptDia,
          width: max(1, _ptDia * 0.2),
          stroke: s.stroke,
          space: _ptDia * 2,
          paths: pointsPath,
          _stroke: null,
          _fill: null
        }, s.points);
        points3.show = fnOrSelf(points3.show);
        points3.filter = fnOrSelf(points3.filter);
        points3.fill = fnOrSelf(points3.fill);
        points3.stroke = fnOrSelf(points3.stroke);
        points3.paths = fnOrSelf(points3.paths);
        points3.pxAlign = s.pxAlign;
      }
      if (showLegend) {
        let rowCells = initLegendRow(s, i);
        legendRows.splice(i, 0, rowCells[0]);
        legendCells.splice(i, 0, rowCells[1]);
        legend.values.push(null);
      }
      if (showCursor) {
        activeIdxs.splice(i, 0, null);
        let pt = null;
        if (cursorOnePt) {
          if (i == 0)
            pt = initCursorPt(s, i);
        } else if (i > 0)
          pt = initCursorPt(s, i);
        cursorPts.splice(i, 0, pt);
        cursorPtsLft.splice(i, 0, 0);
        cursorPtsTop.splice(i, 0, 0);
      }
      fire("addSeries", i);
    }
    function addSeries(opts2, si) {
      si = si == null ? series.length : si;
      opts2 = mode == 1 ? setDefault(opts2, si, xSeriesOpts, ySeriesOpts) : setDefault(opts2, si, {}, xySeriesOpts);
      series.splice(si, 0, opts2);
      initSeries(series[si], si);
    }
    self.addSeries = addSeries;
    function delSeries(i) {
      series.splice(i, 1);
      if (showLegend) {
        legend.values.splice(i, 1);
        legendCells.splice(i, 1);
        let tr = legendRows.splice(i, 1)[0];
        offMouse(null, tr.firstChild);
        tr.remove();
      }
      if (showCursor) {
        activeIdxs.splice(i, 1);
        cursorPts.splice(i, 1)[0].remove();
        cursorPtsLft.splice(i, 1);
        cursorPtsTop.splice(i, 1);
      }
      fire("delSeries", i);
    }
    self.delSeries = delSeries;
    const sidesWithAxes = [false, false, false, false];
    function initAxis(axis, i) {
      axis._show = axis.show;
      if (axis.show) {
        let isVt = axis.side % 2;
        let sc = scales[axis.scale];
        if (sc == null) {
          axis.scale = isVt ? series[1].scale : xScaleKey;
          sc = scales[axis.scale];
        }
        let isTime = sc.time;
        axis.size = fnOrSelf(axis.size);
        axis.space = fnOrSelf(axis.space);
        axis.rotate = fnOrSelf(axis.rotate);
        if (isArr(axis.incrs)) {
          axis.incrs.forEach((incr) => {
            !fixedDec.has(incr) && fixedDec.set(incr, guessDec(incr));
          });
        }
        axis.incrs = fnOrSelf(axis.incrs || (sc.distr == 2 ? wholeIncrs : isTime ? ms == 1 ? timeIncrsMs : timeIncrsS : numIncrs));
        axis.splits = fnOrSelf(axis.splits || (isTime && sc.distr == 1 ? _timeAxisSplits : sc.distr == 3 ? logAxisSplits : sc.distr == 4 ? asinhAxisSplits : numAxisSplits));
        axis.stroke = fnOrSelf(axis.stroke);
        axis.grid.stroke = fnOrSelf(axis.grid.stroke);
        axis.ticks.stroke = fnOrSelf(axis.ticks.stroke);
        axis.border.stroke = fnOrSelf(axis.border.stroke);
        let av = axis.values;
        axis.values = // static array of tick values
        isArr(av) && !isArr(av[0]) ? fnOrSelf(av) : (
          // temporal
          isTime ? (
            // config array of fmtDate string tpls
            isArr(av) ? timeAxisVals(_tzDate, timeAxisStamps(av, _fmtDate)) : (
              // fmtDate string tpl
              isStr(av) ? timeAxisVal(_tzDate, av) : av || _timeAxisVals
            )
          ) : av || numAxisVals
        );
        axis.filter = fnOrSelf(axis.filter || (sc.distr >= 3 && sc.log == 10 ? log10AxisValsFilt : sc.distr == 3 && sc.log == 2 ? log2AxisValsFilt : retArg1));
        axis.font = pxRatioFont(axis.font);
        axis.labelFont = pxRatioFont(axis.labelFont);
        axis._size = axis.size(self, null, i, 0);
        axis._space = axis._rotate = axis._incrs = axis._found = // foundIncrSpace
        axis._splits = axis._values = null;
        if (axis._size > 0) {
          sidesWithAxes[i] = true;
          axis._el = placeDiv(AXIS, wrap);
        }
      }
    }
    function autoPadSide(self2, side, sidesWithAxes2, cycleNum) {
      let [hasTopAxis, hasRgtAxis, hasBtmAxis, hasLftAxis] = sidesWithAxes2;
      let ori = side % 2;
      let size = 0;
      if (ori == 0 && (hasLftAxis || hasRgtAxis))
        size = side == 0 && !hasTopAxis || side == 2 && !hasBtmAxis ? round(xAxisOpts.size / 3) : 0;
      if (ori == 1 && (hasTopAxis || hasBtmAxis))
        size = side == 1 && !hasRgtAxis || side == 3 && !hasLftAxis ? round(yAxisOpts.size / 2) : 0;
      return size;
    }
    const padding = self.padding = (opts.padding || [autoPadSide, autoPadSide, autoPadSide, autoPadSide]).map((p) => fnOrSelf(ifNull(p, autoPadSide)));
    const _padding = self._padding = padding.map((p, i) => p(self, i, sidesWithAxes, 0));
    let dataLen;
    let i0 = null;
    let i1 = null;
    const idxs = mode == 1 ? series[0].idxs : null;
    let data0 = null;
    let viaAutoScaleX = false;
    function setData(_data, _resetScales) {
      data = _data == null ? [] : _data;
      self.data = self._data = data;
      if (mode == 2) {
        dataLen = 0;
        for (let i = 1; i < series.length; i++)
          dataLen += data[i][0].length;
      } else {
        if (data.length == 0)
          self.data = self._data = data = [[]];
        data0 = data[0];
        dataLen = data0.length;
        let scaleData = data;
        if (xScaleDistr == 2) {
          scaleData = data.slice();
          let _data0 = scaleData[0] = Array(dataLen);
          for (let i = 0; i < dataLen; i++)
            _data0[i] = i;
        }
        self._data = data = scaleData;
      }
      resetYSeries(true);
      fire("setData");
      if (xScaleDistr == 2) {
        shouldConvergeSize = true;
      }
      if (_resetScales !== false) {
        let xsc = scaleX;
        if (xsc.auto(self, viaAutoScaleX))
          autoScaleX();
        else
          _setScale(xScaleKey, xsc.min, xsc.max);
        shouldSetCursor = shouldSetCursor || cursor.left >= 0;
        shouldSetLegend = true;
        commit();
      }
    }
    self.setData = setData;
    function autoScaleX() {
      viaAutoScaleX = true;
      let _min, _max;
      if (mode == 1) {
        if (dataLen > 0) {
          i0 = idxs[0] = 0;
          i1 = idxs[1] = dataLen - 1;
          _min = data[0][i0];
          _max = data[0][i1];
          if (xScaleDistr == 2) {
            _min = i0;
            _max = i1;
          } else if (_min == _max) {
            if (xScaleDistr == 3)
              [_min, _max] = rangeLog(_min, _min, scaleX.log, false);
            else if (xScaleDistr == 4)
              [_min, _max] = rangeAsinh(_min, _min, scaleX.log, false);
            else if (scaleX.time)
              _max = _min + round(86400 / ms);
            else
              [_min, _max] = rangeNum(_min, _max, rangePad, true);
          }
        } else {
          i0 = idxs[0] = _min = null;
          i1 = idxs[1] = _max = null;
        }
      }
      _setScale(xScaleKey, _min, _max);
    }
    let ctxStroke, ctxFill, ctxWidth, ctxDash, ctxJoin, ctxCap, ctxFont, ctxAlign, ctxBaseline;
    let ctxAlpha;
    function setCtxStyle(stroke, width, dash, cap, fill, join2) {
      stroke ?? (stroke = transparent);
      dash ?? (dash = EMPTY_ARR);
      cap ?? (cap = "butt");
      fill ?? (fill = transparent);
      join2 ?? (join2 = "round");
      if (stroke != ctxStroke)
        ctx.strokeStyle = ctxStroke = stroke;
      if (fill != ctxFill)
        ctx.fillStyle = ctxFill = fill;
      if (width != ctxWidth)
        ctx.lineWidth = ctxWidth = width;
      if (join2 != ctxJoin)
        ctx.lineJoin = ctxJoin = join2;
      if (cap != ctxCap)
        ctx.lineCap = ctxCap = cap;
      if (dash != ctxDash)
        ctx.setLineDash(ctxDash = dash);
    }
    function setFontStyle(font2, fill, align, baseline) {
      if (fill != ctxFill)
        ctx.fillStyle = ctxFill = fill;
      if (font2 != ctxFont)
        ctx.font = ctxFont = font2;
      if (align != ctxAlign)
        ctx.textAlign = ctxAlign = align;
      if (baseline != ctxBaseline)
        ctx.textBaseline = ctxBaseline = baseline;
    }
    function accScale(wsc, psc, facet2, data2, sorted = 0) {
      if (data2.length > 0 && wsc.auto(self, viaAutoScaleX) && (psc == null || psc.min == null)) {
        let _i0 = ifNull(i0, 0);
        let _i1 = ifNull(i1, data2.length - 1);
        let minMax = facet2.min == null ? getMinMax(data2, _i0, _i1, sorted, wsc.distr == 3) : [facet2.min, facet2.max];
        wsc.min = min(wsc.min, facet2.min = minMax[0]);
        wsc.max = max(wsc.max, facet2.max = minMax[1]);
      }
    }
    const AUTOSCALE = { min: null, max: null };
    function setScales() {
      for (let k in scales) {
        let sc = scales[k];
        if (pendScales[k] == null && // scales that have never been set (on init)
        (sc.min == null || // or auto scales when the x scale was explicitly set
        pendScales[xScaleKey] != null && sc.auto(self, viaAutoScaleX))) {
          pendScales[k] = AUTOSCALE;
        }
      }
      for (let k in scales) {
        let sc = scales[k];
        if (pendScales[k] == null && sc.from != null && pendScales[sc.from] != null)
          pendScales[k] = AUTOSCALE;
      }
      if (pendScales[xScaleKey] != null)
        resetYSeries(true);
      let wipScales = {};
      for (let k in pendScales) {
        let psc = pendScales[k];
        if (psc != null) {
          let wsc = wipScales[k] = copy(scales[k], fastIsObj);
          if (psc.min != null)
            assign(wsc, psc);
          else if (k != xScaleKey || mode == 2) {
            if (dataLen == 0 && wsc.from == null) {
              let minMax = wsc.range(self, null, null, k);
              wsc.min = minMax[0];
              wsc.max = minMax[1];
            } else {
              wsc.min = inf;
              wsc.max = -inf;
            }
          }
        }
      }
      if (dataLen > 0) {
        series.forEach((s, i) => {
          if (mode == 1) {
            let k = s.scale;
            let psc = pendScales[k];
            if (psc == null)
              return;
            let wsc = wipScales[k];
            if (i == 0) {
              let minMax = wsc.range(self, wsc.min, wsc.max, k);
              wsc.min = minMax[0];
              wsc.max = minMax[1];
              i0 = closestIdx(wsc.min, data[0]);
              i1 = closestIdx(wsc.max, data[0]);
              if (i1 - i0 > 1) {
                if (data[0][i0] < wsc.min)
                  i0++;
                if (data[0][i1] > wsc.max)
                  i1--;
              }
              s.min = data0[i0];
              s.max = data0[i1];
            } else if (s.show && s.auto)
              accScale(wsc, psc, s, data[i], s.sorted);
            s.idxs[0] = i0;
            s.idxs[1] = i1;
          } else {
            if (i > 0) {
              if (s.show && s.auto) {
                let [xFacet, yFacet] = s.facets;
                let xScaleKey2 = xFacet.scale;
                let yScaleKey = yFacet.scale;
                let [xData, yData] = data[i];
                let wscx = wipScales[xScaleKey2];
                let wscy = wipScales[yScaleKey];
                wscx != null && accScale(wscx, pendScales[xScaleKey2], xFacet, xData, xFacet.sorted);
                wscy != null && accScale(wscy, pendScales[yScaleKey], yFacet, yData, yFacet.sorted);
                s.min = yFacet.min;
                s.max = yFacet.max;
              }
            }
          }
        });
        for (let k in wipScales) {
          let wsc = wipScales[k];
          let psc = pendScales[k];
          if (wsc.from == null && (psc == null || psc.min == null)) {
            let minMax = wsc.range(
              self,
              wsc.min == inf ? null : wsc.min,
              wsc.max == -inf ? null : wsc.max,
              k
            );
            wsc.min = minMax[0];
            wsc.max = minMax[1];
          }
        }
      }
      for (let k in wipScales) {
        let wsc = wipScales[k];
        if (wsc.from != null) {
          let base = wipScales[wsc.from];
          if (base.min == null)
            wsc.min = wsc.max = null;
          else {
            let minMax = wsc.range(self, base.min, base.max, k);
            wsc.min = minMax[0];
            wsc.max = minMax[1];
          }
        }
      }
      let changed = {};
      let anyChanged = false;
      for (let k in wipScales) {
        let wsc = wipScales[k];
        let sc = scales[k];
        if (sc.min != wsc.min || sc.max != wsc.max) {
          sc.min = wsc.min;
          sc.max = wsc.max;
          let distr = sc.distr;
          sc._min = distr == 3 ? log10(sc.min) : distr == 4 ? asinh(sc.min, sc.asinh) : distr == 100 ? sc.fwd(sc.min) : sc.min;
          sc._max = distr == 3 ? log10(sc.max) : distr == 4 ? asinh(sc.max, sc.asinh) : distr == 100 ? sc.fwd(sc.max) : sc.max;
          changed[k] = anyChanged = true;
        }
      }
      if (anyChanged) {
        series.forEach((s, i) => {
          if (mode == 2) {
            if (i > 0 && changed.y)
              s._paths = null;
          } else {
            if (changed[s.scale])
              s._paths = null;
          }
        });
        for (let k in changed) {
          shouldConvergeSize = true;
          fire("setScale", k);
        }
        if (showCursor && cursor.left >= 0)
          shouldSetCursor = shouldSetLegend = true;
      }
      for (let k in pendScales)
        pendScales[k] = null;
    }
    function getOuterIdxs(ydata) {
      let _i0 = clamp(i0 - 1, 0, dataLen - 1);
      let _i1 = clamp(i1 + 1, 0, dataLen - 1);
      while (ydata[_i0] == null && _i0 > 0)
        _i0--;
      while (ydata[_i1] == null && _i1 < dataLen - 1)
        _i1++;
      return [_i0, _i1];
    }
    function drawSeries() {
      if (dataLen > 0) {
        let shouldAlpha = series.some((s) => s._focus) && ctxAlpha != focus.alpha;
        if (shouldAlpha)
          ctx.globalAlpha = ctxAlpha = focus.alpha;
        series.forEach((s, i) => {
          if (i > 0 && s.show) {
            cacheStrokeFill(i, false);
            cacheStrokeFill(i, true);
            if (s._paths == null) {
              let _ctxAlpha = ctxAlpha;
              if (ctxAlpha != s.alpha)
                ctx.globalAlpha = ctxAlpha = s.alpha;
              let _idxs = mode == 2 ? [0, data[i][0].length - 1] : getOuterIdxs(data[i]);
              s._paths = s.paths(self, i, _idxs[0], _idxs[1]);
              if (ctxAlpha != _ctxAlpha)
                ctx.globalAlpha = ctxAlpha = _ctxAlpha;
            }
          }
        });
        series.forEach((s, i) => {
          if (i > 0 && s.show) {
            let _ctxAlpha = ctxAlpha;
            if (ctxAlpha != s.alpha)
              ctx.globalAlpha = ctxAlpha = s.alpha;
            s._paths != null && drawPath(i, false);
            {
              let _gaps = s._paths != null ? s._paths.gaps : null;
              let show = s.points.show(self, i, i0, i1, _gaps);
              let idxs2 = s.points.filter(self, i, show, _gaps);
              if (show || idxs2) {
                s.points._paths = s.points.paths(self, i, i0, i1, idxs2);
                drawPath(i, true);
              }
            }
            if (ctxAlpha != _ctxAlpha)
              ctx.globalAlpha = ctxAlpha = _ctxAlpha;
            fire("drawSeries", i);
          }
        });
        if (shouldAlpha)
          ctx.globalAlpha = ctxAlpha = 1;
      }
    }
    function cacheStrokeFill(si, _points) {
      let s = _points ? series[si].points : series[si];
      s._stroke = s.stroke(self, si);
      s._fill = s.fill(self, si);
    }
    function drawPath(si, _points) {
      let s = _points ? series[si].points : series[si];
      let {
        stroke,
        fill,
        clip: gapsClip,
        flags,
        _stroke: strokeStyle = s._stroke,
        _fill: fillStyle = s._fill,
        _width: width = s.width
      } = s._paths;
      width = roundDec(width * pxRatio, 3);
      let boundsClip = null;
      let offset = width % 2 / 2;
      if (_points && fillStyle == null)
        fillStyle = width > 0 ? "#fff" : strokeStyle;
      let _pxAlign = s.pxAlign == 1 && offset > 0;
      _pxAlign && ctx.translate(offset, offset);
      if (!_points) {
        let lft = plotLft - width / 2, top = plotTop - width / 2, wid = plotWid + width, hgt = plotHgt + width;
        boundsClip = new Path2D();
        boundsClip.rect(lft, top, wid, hgt);
      }
      if (_points)
        strokeFill(strokeStyle, width, s.dash, s.cap, fillStyle, stroke, fill, flags, gapsClip);
      else
        fillStroke(si, strokeStyle, width, s.dash, s.cap, fillStyle, stroke, fill, flags, boundsClip, gapsClip);
      _pxAlign && ctx.translate(-offset, -offset);
    }
    function fillStroke(si, strokeStyle, lineWidth, lineDash, lineCap, fillStyle, strokePath, fillPath, flags, boundsClip, gapsClip) {
      let didStrokeFill = false;
      flags != 0 && bands.forEach((b, bi) => {
        if (b.series[0] == si) {
          let lowerEdge = series[b.series[1]];
          let lowerData = data[b.series[1]];
          let bandClip = (lowerEdge._paths || EMPTY_OBJ).band;
          if (isArr(bandClip))
            bandClip = b.dir == 1 ? bandClip[0] : bandClip[1];
          let gapsClip2;
          let _fillStyle = null;
          if (lowerEdge.show && bandClip && hasData(lowerData, i0, i1)) {
            _fillStyle = b.fill(self, bi) || fillStyle;
            gapsClip2 = lowerEdge._paths.clip;
          } else
            bandClip = null;
          strokeFill(strokeStyle, lineWidth, lineDash, lineCap, _fillStyle, strokePath, fillPath, flags, boundsClip, gapsClip, gapsClip2, bandClip);
          didStrokeFill = true;
        }
      });
      if (!didStrokeFill)
        strokeFill(strokeStyle, lineWidth, lineDash, lineCap, fillStyle, strokePath, fillPath, flags, boundsClip, gapsClip);
    }
    const CLIP_FILL_STROKE = BAND_CLIP_FILL | BAND_CLIP_STROKE;
    function strokeFill(strokeStyle, lineWidth, lineDash, lineCap, fillStyle, strokePath, fillPath, flags, boundsClip, gapsClip, gapsClip2, bandClip) {
      setCtxStyle(strokeStyle, lineWidth, lineDash, lineCap, fillStyle);
      if (boundsClip || gapsClip || bandClip) {
        ctx.save();
        boundsClip && ctx.clip(boundsClip);
        gapsClip && ctx.clip(gapsClip);
      }
      if (bandClip) {
        if ((flags & CLIP_FILL_STROKE) == CLIP_FILL_STROKE) {
          ctx.clip(bandClip);
          gapsClip2 && ctx.clip(gapsClip2);
          doFill(fillStyle, fillPath);
          doStroke(strokeStyle, strokePath, lineWidth);
        } else if (flags & BAND_CLIP_STROKE) {
          doFill(fillStyle, fillPath);
          ctx.clip(bandClip);
          doStroke(strokeStyle, strokePath, lineWidth);
        } else if (flags & BAND_CLIP_FILL) {
          ctx.save();
          ctx.clip(bandClip);
          gapsClip2 && ctx.clip(gapsClip2);
          doFill(fillStyle, fillPath);
          ctx.restore();
          doStroke(strokeStyle, strokePath, lineWidth);
        }
      } else {
        doFill(fillStyle, fillPath);
        doStroke(strokeStyle, strokePath, lineWidth);
      }
      if (boundsClip || gapsClip || bandClip)
        ctx.restore();
    }
    function doStroke(strokeStyle, strokePath, lineWidth) {
      if (lineWidth > 0) {
        if (strokePath instanceof Map) {
          strokePath.forEach((strokePath2, strokeStyle2) => {
            ctx.strokeStyle = ctxStroke = strokeStyle2;
            ctx.stroke(strokePath2);
          });
        } else
          strokePath != null && strokeStyle && ctx.stroke(strokePath);
      }
    }
    function doFill(fillStyle, fillPath) {
      if (fillPath instanceof Map) {
        fillPath.forEach((fillPath2, fillStyle2) => {
          ctx.fillStyle = ctxFill = fillStyle2;
          ctx.fill(fillPath2);
        });
      } else
        fillPath != null && fillStyle && ctx.fill(fillPath);
    }
    function getIncrSpace(axisIdx, min2, max2, fullDim) {
      let axis = axes[axisIdx];
      let incrSpace;
      if (fullDim <= 0)
        incrSpace = [0, 0];
      else {
        let minSpace = axis._space = axis.space(self, axisIdx, min2, max2, fullDim);
        let incrs = axis._incrs = axis.incrs(self, axisIdx, min2, max2, fullDim, minSpace);
        incrSpace = findIncr(min2, max2, incrs, fullDim, minSpace);
      }
      return axis._found = incrSpace;
    }
    function drawOrthoLines(offs, filts, ori, side, pos0, len, width, stroke, dash, cap) {
      let offset = width % 2 / 2;
      pxAlign == 1 && ctx.translate(offset, offset);
      setCtxStyle(stroke, width, dash, cap, stroke);
      ctx.beginPath();
      let x0, y0, x1, y1, pos1 = pos0 + (side == 0 || side == 3 ? -len : len);
      if (ori == 0) {
        y0 = pos0;
        y1 = pos1;
      } else {
        x0 = pos0;
        x1 = pos1;
      }
      for (let i = 0; i < offs.length; i++) {
        if (filts[i] != null) {
          if (ori == 0)
            x0 = x1 = offs[i];
          else
            y0 = y1 = offs[i];
          ctx.moveTo(x0, y0);
          ctx.lineTo(x1, y1);
        }
      }
      ctx.stroke();
      pxAlign == 1 && ctx.translate(-offset, -offset);
    }
    function axesCalc(cycleNum) {
      let converged = true;
      axes.forEach((axis, i) => {
        if (!axis.show)
          return;
        let scale = scales[axis.scale];
        if (scale.min == null) {
          if (axis._show) {
            converged = false;
            axis._show = false;
            resetYSeries(false);
          }
          return;
        } else {
          if (!axis._show) {
            converged = false;
            axis._show = true;
            resetYSeries(false);
          }
        }
        let side = axis.side;
        let ori = side % 2;
        let { min: min2, max: max2 } = scale;
        let [_incr, _space] = getIncrSpace(i, min2, max2, ori == 0 ? plotWidCss : plotHgtCss);
        if (_space == 0)
          return;
        let forceMin = scale.distr == 2;
        let _splits = axis._splits = axis.splits(self, i, min2, max2, _incr, _space, forceMin);
        let splits = scale.distr == 2 ? _splits.map((i2) => data0[i2]) : _splits;
        let incr = scale.distr == 2 ? data0[_splits[1]] - data0[_splits[0]] : _incr;
        let values = axis._values = axis.values(self, axis.filter(self, splits, i, _space, incr), i, _space, incr);
        axis._rotate = side == 2 ? axis.rotate(self, values, i, _space) : 0;
        let oldSize = axis._size;
        axis._size = ceil(axis.size(self, values, i, cycleNum));
        if (oldSize != null && axis._size != oldSize)
          converged = false;
      });
      return converged;
    }
    function paddingCalc(cycleNum) {
      let converged = true;
      padding.forEach((p, i) => {
        let _p = p(self, i, sidesWithAxes, cycleNum);
        if (_p != _padding[i])
          converged = false;
        _padding[i] = _p;
      });
      return converged;
    }
    function drawAxesGrid() {
      for (let i = 0; i < axes.length; i++) {
        let axis = axes[i];
        if (!axis.show || !axis._show)
          continue;
        let side = axis.side;
        let ori = side % 2;
        let x, y;
        let fillStyle = axis.stroke(self, i);
        let shiftDir = side == 0 || side == 3 ? -1 : 1;
        let [_incr, _space] = axis._found;
        if (axis.label != null) {
          let shiftAmt2 = axis.labelGap * shiftDir;
          let baseLpos = round((axis._lpos + shiftAmt2) * pxRatio);
          setFontStyle(axis.labelFont[0], fillStyle, "center", side == 2 ? TOP : BOTTOM);
          ctx.save();
          if (ori == 1) {
            x = y = 0;
            ctx.translate(
              baseLpos,
              round(plotTop + plotHgt / 2)
            );
            ctx.rotate((side == 3 ? -PI : PI) / 2);
          } else {
            x = round(plotLft + plotWid / 2);
            y = baseLpos;
          }
          let _label = isFn(axis.label) ? axis.label(self, i, _incr, _space) : axis.label;
          ctx.fillText(_label, x, y);
          ctx.restore();
        }
        if (_space == 0)
          continue;
        let scale = scales[axis.scale];
        let plotDim = ori == 0 ? plotWid : plotHgt;
        let plotOff = ori == 0 ? plotLft : plotTop;
        let _splits = axis._splits;
        let splits = scale.distr == 2 ? _splits.map((i2) => data0[i2]) : _splits;
        let incr = scale.distr == 2 ? data0[_splits[1]] - data0[_splits[0]] : _incr;
        let ticks2 = axis.ticks;
        let border2 = axis.border;
        let _tickSize = ticks2.show ? ticks2.size : 0;
        let tickSize = round(_tickSize * pxRatio);
        let axisGap = round((axis.alignTo == 2 ? axis._size - _tickSize - axis.gap : axis.gap) * pxRatio);
        let angle = axis._rotate * -PI / 180;
        let basePos = pxRound(axis._pos * pxRatio);
        let shiftAmt = (tickSize + axisGap) * shiftDir;
        let finalPos = basePos + shiftAmt;
        y = ori == 0 ? finalPos : 0;
        x = ori == 1 ? finalPos : 0;
        let font2 = axis.font[0];
        let textAlign = axis.align == 1 ? LEFT : axis.align == 2 ? RIGHT : angle > 0 ? LEFT : angle < 0 ? RIGHT : ori == 0 ? "center" : side == 3 ? RIGHT : LEFT;
        let textBaseline = angle || ori == 1 ? "middle" : side == 2 ? TOP : BOTTOM;
        setFontStyle(font2, fillStyle, textAlign, textBaseline);
        let lineHeight = axis.font[1] * axis.lineGap;
        let canOffs = _splits.map((val) => pxRound(getPos(val, scale, plotDim, plotOff)));
        let _values = axis._values;
        for (let i2 = 0; i2 < _values.length; i2++) {
          let val = _values[i2];
          if (val != null) {
            if (ori == 0)
              x = canOffs[i2];
            else
              y = canOffs[i2];
            val = "" + val;
            let _parts = val.indexOf("\n") == -1 ? [val] : val.split(/\n/gm);
            for (let j = 0; j < _parts.length; j++) {
              let text = _parts[j];
              if (angle) {
                ctx.save();
                ctx.translate(x, y + j * lineHeight);
                ctx.rotate(angle);
                ctx.fillText(text, 0, 0);
                ctx.restore();
              } else
                ctx.fillText(text, x, y + j * lineHeight);
            }
          }
        }
        if (ticks2.show) {
          drawOrthoLines(
            canOffs,
            ticks2.filter(self, splits, i, _space, incr),
            ori,
            side,
            basePos,
            tickSize,
            roundDec(ticks2.width * pxRatio, 3),
            ticks2.stroke(self, i),
            ticks2.dash,
            ticks2.cap
          );
        }
        let grid2 = axis.grid;
        if (grid2.show) {
          drawOrthoLines(
            canOffs,
            grid2.filter(self, splits, i, _space, incr),
            ori,
            ori == 0 ? 2 : 1,
            ori == 0 ? plotTop : plotLft,
            ori == 0 ? plotHgt : plotWid,
            roundDec(grid2.width * pxRatio, 3),
            grid2.stroke(self, i),
            grid2.dash,
            grid2.cap
          );
        }
        if (border2.show) {
          drawOrthoLines(
            [basePos],
            [1],
            ori == 0 ? 1 : 0,
            ori == 0 ? 1 : 2,
            ori == 1 ? plotTop : plotLft,
            ori == 1 ? plotHgt : plotWid,
            roundDec(border2.width * pxRatio, 3),
            border2.stroke(self, i),
            border2.dash,
            border2.cap
          );
        }
      }
      fire("drawAxes");
    }
    function resetYSeries(minMax) {
      series.forEach((s, i) => {
        if (i > 0) {
          s._paths = null;
          if (minMax) {
            if (mode == 1) {
              s.min = null;
              s.max = null;
            } else {
              s.facets.forEach((f) => {
                f.min = null;
                f.max = null;
              });
            }
          }
        }
      });
    }
    let queuedCommit = false;
    let deferHooks = false;
    let hooksQueue = [];
    function flushHooks() {
      deferHooks = false;
      for (let i = 0; i < hooksQueue.length; i++)
        fire(...hooksQueue[i]);
      hooksQueue.length = 0;
    }
    function commit() {
      if (!queuedCommit) {
        microTask(_commit);
        queuedCommit = true;
      }
    }
    function batch(fn, _deferHooks = false) {
      queuedCommit = true;
      deferHooks = _deferHooks;
      fn(self);
      _commit();
      if (_deferHooks && hooksQueue.length > 0)
        queueMicrotask(flushHooks);
    }
    self.batch = batch;
    function _commit() {
      if (shouldSetScales) {
        setScales();
        shouldSetScales = false;
      }
      if (shouldConvergeSize) {
        convergeSize();
        shouldConvergeSize = false;
      }
      if (shouldSetSize) {
        setStylePx(under, LEFT, plotLftCss);
        setStylePx(under, TOP, plotTopCss);
        setStylePx(under, WIDTH, plotWidCss);
        setStylePx(under, HEIGHT, plotHgtCss);
        setStylePx(over, LEFT, plotLftCss);
        setStylePx(over, TOP, plotTopCss);
        setStylePx(over, WIDTH, plotWidCss);
        setStylePx(over, HEIGHT, plotHgtCss);
        setStylePx(wrap, WIDTH, fullWidCss);
        setStylePx(wrap, HEIGHT, fullHgtCss);
        can.width = round(fullWidCss * pxRatio);
        can.height = round(fullHgtCss * pxRatio);
        axes.forEach(({ _el, _show, _size, _pos, side }) => {
          if (_el != null) {
            if (_show) {
              let posOffset = side === 3 || side === 0 ? _size : 0;
              let isVt = side % 2 == 1;
              setStylePx(_el, isVt ? "left" : "top", _pos - posOffset);
              setStylePx(_el, isVt ? "width" : "height", _size);
              setStylePx(_el, isVt ? "top" : "left", isVt ? plotTopCss : plotLftCss);
              setStylePx(_el, isVt ? "height" : "width", isVt ? plotHgtCss : plotWidCss);
              remClass(_el, OFF);
            } else
              addClass(_el, OFF);
          }
        });
        ctxStroke = ctxFill = ctxWidth = ctxJoin = ctxCap = ctxFont = ctxAlign = ctxBaseline = ctxDash = null;
        ctxAlpha = 1;
        syncRect(true);
        if (plotLftCss != _plotLftCss || plotTopCss != _plotTopCss || plotWidCss != _plotWidCss || plotHgtCss != _plotHgtCss) {
          resetYSeries(false);
          let pctWid = plotWidCss / _plotWidCss;
          let pctHgt = plotHgtCss / _plotHgtCss;
          if (showCursor && !shouldSetCursor && cursor.left >= 0) {
            cursor.left *= pctWid;
            cursor.top *= pctHgt;
            vCursor && elTrans(vCursor, round(cursor.left), 0, plotWidCss, plotHgtCss);
            hCursor && elTrans(hCursor, 0, round(cursor.top), plotWidCss, plotHgtCss);
            for (let i = 0; i < cursorPts.length; i++) {
              let pt = cursorPts[i];
              if (pt != null) {
                cursorPtsLft[i] *= pctWid;
                cursorPtsTop[i] *= pctHgt;
                elTrans(pt, ceil(cursorPtsLft[i]), ceil(cursorPtsTop[i]), plotWidCss, plotHgtCss);
              }
            }
          }
          if (select.show && !shouldSetSelect && select.left >= 0 && select.width > 0) {
            select.left *= pctWid;
            select.width *= pctWid;
            select.top *= pctHgt;
            select.height *= pctHgt;
            for (let prop in _hideProps)
              setStylePx(selectDiv, prop, select[prop]);
          }
          _plotLftCss = plotLftCss;
          _plotTopCss = plotTopCss;
          _plotWidCss = plotWidCss;
          _plotHgtCss = plotHgtCss;
        }
        fire("setSize");
        shouldSetSize = false;
      }
      if (fullWidCss > 0 && fullHgtCss > 0) {
        ctx.clearRect(0, 0, can.width, can.height);
        fire("drawClear");
        drawOrder.forEach((fn) => fn());
        fire("draw");
      }
      if (select.show && shouldSetSelect) {
        setSelect(select);
        shouldSetSelect = false;
      }
      if (showCursor && shouldSetCursor) {
        updateCursor(null, true, false);
        shouldSetCursor = false;
      }
      if (legend.show && legend.live && shouldSetLegend) {
        setLegend();
        shouldSetLegend = false;
      }
      if (!ready) {
        ready = true;
        self.status = 1;
        fire("ready");
      }
      viaAutoScaleX = false;
      queuedCommit = false;
    }
    self.redraw = (rebuildPaths, recalcAxes) => {
      shouldConvergeSize = recalcAxes || false;
      if (rebuildPaths !== false)
        _setScale(xScaleKey, scaleX.min, scaleX.max);
      else
        commit();
    };
    function setScale(key2, opts2) {
      let sc = scales[key2];
      if (sc.from == null) {
        if (dataLen == 0) {
          let minMax = sc.range(self, opts2.min, opts2.max, key2);
          opts2.min = minMax[0];
          opts2.max = minMax[1];
        }
        if (opts2.min > opts2.max) {
          let _min = opts2.min;
          opts2.min = opts2.max;
          opts2.max = _min;
        }
        if (dataLen > 1 && opts2.min != null && opts2.max != null && opts2.max - opts2.min < 1e-16)
          return;
        if (key2 == xScaleKey) {
          if (sc.distr == 2 && dataLen > 0) {
            opts2.min = closestIdx(opts2.min, data[0]);
            opts2.max = closestIdx(opts2.max, data[0]);
            if (opts2.min == opts2.max)
              opts2.max++;
          }
        }
        pendScales[key2] = opts2;
        shouldSetScales = true;
        commit();
      }
    }
    self.setScale = setScale;
    let xCursor;
    let yCursor;
    let vCursor;
    let hCursor;
    let rawMouseLeft0;
    let rawMouseTop0;
    let mouseLeft0;
    let mouseTop0;
    let rawMouseLeft1;
    let rawMouseTop1;
    let mouseLeft1;
    let mouseTop1;
    let dragging = false;
    const drag = cursor.drag;
    let dragX = drag.x;
    let dragY = drag.y;
    if (showCursor) {
      if (cursor.x)
        xCursor = placeDiv(CURSOR_X, over);
      if (cursor.y)
        yCursor = placeDiv(CURSOR_Y, over);
      if (scaleX.ori == 0) {
        vCursor = xCursor;
        hCursor = yCursor;
      } else {
        vCursor = yCursor;
        hCursor = xCursor;
      }
      mouseLeft1 = cursor.left;
      mouseTop1 = cursor.top;
    }
    const select = self.select = assign({
      show: true,
      over: true,
      left: 0,
      width: 0,
      top: 0,
      height: 0
    }, opts.select);
    const selectDiv = select.show ? placeDiv(SELECT, select.over ? over : under) : null;
    function setSelect(opts2, _fire) {
      if (select.show) {
        for (let prop in opts2) {
          select[prop] = opts2[prop];
          if (prop in _hideProps)
            setStylePx(selectDiv, prop, opts2[prop]);
        }
        _fire !== false && fire("setSelect");
      }
    }
    self.setSelect = setSelect;
    function toggleDOM(i) {
      let s = series[i];
      if (s.show)
        showLegend && remClass(legendRows[i], OFF);
      else {
        showLegend && addClass(legendRows[i], OFF);
        if (showCursor) {
          let pt = cursorOnePt ? cursorPts[0] : cursorPts[i];
          pt != null && elTrans(pt, -10, -10, plotWidCss, plotHgtCss);
        }
      }
    }
    function _setScale(key2, min2, max2) {
      setScale(key2, { min: min2, max: max2 });
    }
    function setSeries(i, opts2, _fire, _pub) {
      if (opts2.focus != null)
        setFocus(i);
      if (opts2.show != null) {
        series.forEach((s, si) => {
          if (si > 0 && (i == si || i == null)) {
            s.show = opts2.show;
            toggleDOM(si);
            if (mode == 2) {
              _setScale(s.facets[0].scale, null, null);
              _setScale(s.facets[1].scale, null, null);
            } else
              _setScale(s.scale, null, null);
            commit();
          }
        });
      }
      _fire !== false && fire("setSeries", i, opts2);
      _pub && pubSync("setSeries", self, i, opts2);
    }
    self.setSeries = setSeries;
    function setBand(bi, opts2) {
      assign(bands[bi], opts2);
    }
    function addBand(opts2, bi) {
      opts2.fill = fnOrSelf(opts2.fill || null);
      opts2.dir = ifNull(opts2.dir, -1);
      bi = bi == null ? bands.length : bi;
      bands.splice(bi, 0, opts2);
    }
    function delBand(bi) {
      if (bi == null)
        bands.length = 0;
      else
        bands.splice(bi, 1);
    }
    self.addBand = addBand;
    self.setBand = setBand;
    self.delBand = delBand;
    function setAlpha(i, value) {
      series[i].alpha = value;
      if (showCursor && cursorPts[i] != null)
        cursorPts[i].style.opacity = value;
      if (showLegend && legendRows[i])
        legendRows[i].style.opacity = value;
    }
    let closestDist;
    let closestSeries;
    let focusedSeries;
    const FOCUS_TRUE = { focus: true };
    function setFocus(i) {
      if (i != focusedSeries) {
        let allFocused = i == null;
        let _setAlpha = focus.alpha != 1;
        series.forEach((s, i2) => {
          if (mode == 1 || i2 > 0) {
            let isFocused = allFocused || i2 == 0 || i2 == i;
            s._focus = allFocused ? null : isFocused;
            _setAlpha && setAlpha(i2, isFocused ? 1 : focus.alpha);
          }
        });
        focusedSeries = i;
        _setAlpha && commit();
      }
    }
    if (showLegend && cursorFocus) {
      onMouse(mouseleave, legendTable, (e) => {
        if (cursor._lock)
          return;
        setCursorEvent(e);
        if (focusedSeries != null)
          setSeries(null, FOCUS_TRUE, true, syncOpts.setSeries);
      });
    }
    function posToVal(pos, scale, can2) {
      let sc = scales[scale];
      if (can2)
        pos = pos / pxRatio - (sc.ori == 1 ? plotTopCss : plotLftCss);
      let dim = plotWidCss;
      if (sc.ori == 1) {
        dim = plotHgtCss;
        pos = dim - pos;
      }
      if (sc.dir == -1)
        pos = dim - pos;
      let _min = sc._min, _max = sc._max, pct = pos / dim;
      let sv = _min + (_max - _min) * pct;
      let distr = sc.distr;
      return distr == 3 ? pow(10, sv) : distr == 4 ? sinh(sv, sc.asinh) : distr == 100 ? sc.bwd(sv) : sv;
    }
    function closestIdxFromXpos(pos, can2) {
      let v = posToVal(pos, xScaleKey, can2);
      return closestIdx(v, data[0], i0, i1);
    }
    self.valToIdx = (val) => closestIdx(val, data[0]);
    self.posToIdx = closestIdxFromXpos;
    self.posToVal = posToVal;
    self.valToPos = (val, scale, can2) => scales[scale].ori == 0 ? getHPos(
      val,
      scales[scale],
      can2 ? plotWid : plotWidCss,
      can2 ? plotLft : 0
    ) : getVPos(
      val,
      scales[scale],
      can2 ? plotHgt : plotHgtCss,
      can2 ? plotTop : 0
    );
    self.setCursor = (opts2, _fire, _pub) => {
      mouseLeft1 = opts2.left;
      mouseTop1 = opts2.top;
      updateCursor(null, _fire, _pub);
    };
    function setSelH(off2, dim) {
      setStylePx(selectDiv, LEFT, select.left = off2);
      setStylePx(selectDiv, WIDTH, select.width = dim);
    }
    function setSelV(off2, dim) {
      setStylePx(selectDiv, TOP, select.top = off2);
      setStylePx(selectDiv, HEIGHT, select.height = dim);
    }
    let setSelX = scaleX.ori == 0 ? setSelH : setSelV;
    let setSelY = scaleX.ori == 1 ? setSelH : setSelV;
    function syncLegend() {
      if (showLegend && legend.live) {
        for (let i = mode == 2 ? 1 : 0; i < series.length; i++) {
          if (i == 0 && multiValLegend)
            continue;
          let vals = legend.values[i];
          let j = 0;
          for (let k in vals)
            legendCells[i][j++].firstChild.nodeValue = vals[k];
        }
      }
    }
    function setLegend(opts2, _fire) {
      if (opts2 != null) {
        if (opts2.idxs) {
          opts2.idxs.forEach((didx, sidx) => {
            activeIdxs[sidx] = didx;
          });
        } else if (!isUndef(opts2.idx))
          activeIdxs.fill(opts2.idx);
        legend.idx = activeIdxs[0];
      }
      if (showLegend && legend.live) {
        for (let sidx = 0; sidx < series.length; sidx++) {
          if (sidx > 0 || mode == 1 && !multiValLegend)
            setLegendValues(sidx, activeIdxs[sidx]);
        }
        syncLegend();
      }
      shouldSetLegend = false;
      _fire !== false && fire("setLegend");
    }
    self.setLegend = setLegend;
    function setLegendValues(sidx, idx) {
      let s = series[sidx];
      let src = sidx == 0 && xScaleDistr == 2 ? data0 : data[sidx];
      let val;
      if (multiValLegend)
        val = s.values(self, sidx, idx) ?? NULL_LEGEND_VALUES;
      else {
        val = s.value(self, idx == null ? null : src[idx], sidx, idx);
        val = val == null ? NULL_LEGEND_VALUES : { _: val };
      }
      legend.values[sidx] = val;
    }
    function updateCursor(src, _fire, _pub) {
      rawMouseLeft1 = mouseLeft1;
      rawMouseTop1 = mouseTop1;
      [mouseLeft1, mouseTop1] = cursor.move(self, mouseLeft1, mouseTop1);
      cursor.left = mouseLeft1;
      cursor.top = mouseTop1;
      if (showCursor) {
        vCursor && elTrans(vCursor, round(mouseLeft1), 0, plotWidCss, plotHgtCss);
        hCursor && elTrans(hCursor, 0, round(mouseTop1), plotWidCss, plotHgtCss);
      }
      let idx;
      let noDataInRange = i0 > i1;
      closestDist = inf;
      closestSeries = null;
      let xDim = scaleX.ori == 0 ? plotWidCss : plotHgtCss;
      let yDim = scaleX.ori == 1 ? plotWidCss : plotHgtCss;
      if (mouseLeft1 < 0 || dataLen == 0 || noDataInRange) {
        idx = cursor.idx = null;
        for (let i = 0; i < series.length; i++) {
          let pt = cursorPts[i];
          pt != null && elTrans(pt, -10, -10, plotWidCss, plotHgtCss);
        }
        if (cursorFocus)
          setSeries(null, FOCUS_TRUE, true, src == null && syncOpts.setSeries);
        if (legend.live) {
          activeIdxs.fill(idx);
          shouldSetLegend = true;
        }
      } else {
        let mouseXPos, valAtPosX, xPos;
        if (mode == 1) {
          mouseXPos = scaleX.ori == 0 ? mouseLeft1 : mouseTop1;
          valAtPosX = posToVal(mouseXPos, xScaleKey);
          idx = cursor.idx = closestIdx(valAtPosX, data[0], i0, i1);
          xPos = valToPosX(data[0][idx], scaleX, xDim, 0);
        }
        let _ptLft = -10;
        let _ptTop = -10;
        let _ptWid = 0;
        let _ptHgt = 0;
        let _centered = true;
        let _ptFill = "";
        let _ptStroke = "";
        for (let i = mode == 2 ? 1 : 0; i < series.length; i++) {
          let s = series[i];
          let idx1 = activeIdxs[i];
          let yVal1 = idx1 == null ? null : mode == 1 ? data[i][idx1] : data[i][1][idx1];
          let idx2 = cursor.dataIdx(self, i, idx, valAtPosX);
          let yVal2 = idx2 == null ? null : mode == 1 ? data[i][idx2] : data[i][1][idx2];
          shouldSetLegend = shouldSetLegend || yVal2 != yVal1 || idx2 != idx1;
          activeIdxs[i] = idx2;
          if (i > 0 && s.show) {
            let xPos2 = idx2 == null ? -10 : idx2 == idx ? xPos : valToPosX(mode == 1 ? data[0][idx2] : data[i][0][idx2], scaleX, xDim, 0);
            let yPos = yVal2 == null ? -10 : valToPosY(yVal2, mode == 1 ? scales[s.scale] : scales[s.facets[1].scale], yDim, 0);
            if (cursorFocus && yVal2 != null) {
              let mouseYPos = scaleX.ori == 1 ? mouseLeft1 : mouseTop1;
              let dist = abs(focus.dist(self, i, idx2, yPos, mouseYPos));
              if (dist < closestDist) {
                let bias = focus.bias;
                if (bias != 0) {
                  let mouseYVal = posToVal(mouseYPos, s.scale);
                  let seriesYValSign = yVal2 >= 0 ? 1 : -1;
                  let mouseYValSign = mouseYVal >= 0 ? 1 : -1;
                  if (mouseYValSign == seriesYValSign && (mouseYValSign == 1 ? bias == 1 ? yVal2 >= mouseYVal : yVal2 <= mouseYVal : (
                    // >= 0
                    bias == 1 ? yVal2 <= mouseYVal : yVal2 >= mouseYVal
                  ))) {
                    closestDist = dist;
                    closestSeries = i;
                  }
                } else {
                  closestDist = dist;
                  closestSeries = i;
                }
              }
            }
            if (shouldSetLegend || cursorOnePt) {
              let hPos, vPos;
              if (scaleX.ori == 0) {
                hPos = xPos2;
                vPos = yPos;
              } else {
                hPos = yPos;
                vPos = xPos2;
              }
              let ptWid, ptHgt, ptLft, ptTop, ptStroke, ptFill, centered = true, getBBox = points2.bbox;
              if (getBBox != null) {
                centered = false;
                let bbox = getBBox(self, i);
                ptLft = bbox.left;
                ptTop = bbox.top;
                ptWid = bbox.width;
                ptHgt = bbox.height;
              } else {
                ptLft = hPos;
                ptTop = vPos;
                ptWid = ptHgt = points2.size(self, i);
              }
              ptFill = points2.fill(self, i);
              ptStroke = points2.stroke(self, i);
              if (cursorOnePt) {
                if (i == closestSeries && closestDist <= focus.prox) {
                  _ptLft = ptLft;
                  _ptTop = ptTop;
                  _ptWid = ptWid;
                  _ptHgt = ptHgt;
                  _centered = centered;
                  _ptFill = ptFill;
                  _ptStroke = ptStroke;
                }
              } else {
                let pt = cursorPts[i];
                if (pt != null) {
                  cursorPtsLft[i] = ptLft;
                  cursorPtsTop[i] = ptTop;
                  elSize(pt, ptWid, ptHgt, centered);
                  elColor(pt, ptFill, ptStroke);
                  elTrans(pt, ceil(ptLft), ceil(ptTop), plotWidCss, plotHgtCss);
                }
              }
            }
          }
        }
        if (cursorOnePt) {
          let p = focus.prox;
          let focusChanged = focusedSeries == null ? closestDist <= p : closestDist > p || closestSeries != focusedSeries;
          if (shouldSetLegend || focusChanged) {
            let pt = cursorPts[0];
            if (pt != null) {
              cursorPtsLft[0] = _ptLft;
              cursorPtsTop[0] = _ptTop;
              elSize(pt, _ptWid, _ptHgt, _centered);
              elColor(pt, _ptFill, _ptStroke);
              elTrans(pt, ceil(_ptLft), ceil(_ptTop), plotWidCss, plotHgtCss);
            }
          }
        }
      }
      if (select.show && dragging) {
        if (src != null) {
          let [xKey, yKey] = syncOpts.scales;
          let [matchXKeys, matchYKeys] = syncOpts.match;
          let [xKeySrc, yKeySrc] = src.cursor.sync.scales;
          let sdrag = src.cursor.drag;
          dragX = sdrag._x;
          dragY = sdrag._y;
          if (dragX || dragY) {
            let { left, top, width, height } = src.select;
            let sori = src.scales[xKeySrc].ori;
            let sPosToVal = src.posToVal;
            let sOff, sDim, sc, a, b;
            let matchingX = xKey != null && matchXKeys(xKey, xKeySrc);
            let matchingY = yKey != null && matchYKeys(yKey, yKeySrc);
            if (matchingX && dragX) {
              if (sori == 0) {
                sOff = left;
                sDim = width;
              } else {
                sOff = top;
                sDim = height;
              }
              sc = scales[xKey];
              a = valToPosX(sPosToVal(sOff, xKeySrc), sc, xDim, 0);
              b = valToPosX(sPosToVal(sOff + sDim, xKeySrc), sc, xDim, 0);
              setSelX(min(a, b), abs(b - a));
            } else
              setSelX(0, xDim);
            if (matchingY && dragY) {
              if (sori == 1) {
                sOff = left;
                sDim = width;
              } else {
                sOff = top;
                sDim = height;
              }
              sc = scales[yKey];
              a = valToPosY(sPosToVal(sOff, yKeySrc), sc, yDim, 0);
              b = valToPosY(sPosToVal(sOff + sDim, yKeySrc), sc, yDim, 0);
              setSelY(min(a, b), abs(b - a));
            } else
              setSelY(0, yDim);
          } else
            hideSelect();
        } else {
          let rawDX = abs(rawMouseLeft1 - rawMouseLeft0);
          let rawDY = abs(rawMouseTop1 - rawMouseTop0);
          if (scaleX.ori == 1) {
            let _rawDX = rawDX;
            rawDX = rawDY;
            rawDY = _rawDX;
          }
          dragX = drag.x && rawDX >= drag.dist;
          dragY = drag.y && rawDY >= drag.dist;
          let uni = drag.uni;
          if (uni != null) {
            if (dragX && dragY) {
              dragX = rawDX >= uni;
              dragY = rawDY >= uni;
              if (!dragX && !dragY) {
                if (rawDY > rawDX)
                  dragY = true;
                else
                  dragX = true;
              }
            }
          } else if (drag.x && drag.y && (dragX || dragY))
            dragX = dragY = true;
          let p0, p1;
          if (dragX) {
            if (scaleX.ori == 0) {
              p0 = mouseLeft0;
              p1 = mouseLeft1;
            } else {
              p0 = mouseTop0;
              p1 = mouseTop1;
            }
            setSelX(min(p0, p1), abs(p1 - p0));
            if (!dragY)
              setSelY(0, yDim);
          }
          if (dragY) {
            if (scaleX.ori == 1) {
              p0 = mouseLeft0;
              p1 = mouseLeft1;
            } else {
              p0 = mouseTop0;
              p1 = mouseTop1;
            }
            setSelY(min(p0, p1), abs(p1 - p0));
            if (!dragX)
              setSelX(0, xDim);
          }
          if (!dragX && !dragY) {
            setSelX(0, 0);
            setSelY(0, 0);
          }
        }
      }
      drag._x = dragX;
      drag._y = dragY;
      if (src == null) {
        if (_pub) {
          if (syncKey != null) {
            let [xSyncKey, ySyncKey] = syncOpts.scales;
            syncOpts.values[0] = xSyncKey != null ? posToVal(scaleX.ori == 0 ? mouseLeft1 : mouseTop1, xSyncKey) : null;
            syncOpts.values[1] = ySyncKey != null ? posToVal(scaleX.ori == 1 ? mouseLeft1 : mouseTop1, ySyncKey) : null;
          }
          pubSync(mousemove, self, mouseLeft1, mouseTop1, plotWidCss, plotHgtCss, idx);
        }
        if (cursorFocus) {
          let shouldPub = _pub && syncOpts.setSeries;
          let p = focus.prox;
          if (focusedSeries == null) {
            if (closestDist <= p)
              setSeries(closestSeries, FOCUS_TRUE, true, shouldPub);
          } else {
            if (closestDist > p)
              setSeries(null, FOCUS_TRUE, true, shouldPub);
            else if (closestSeries != focusedSeries)
              setSeries(closestSeries, FOCUS_TRUE, true, shouldPub);
          }
        }
      }
      if (shouldSetLegend) {
        legend.idx = idx;
        setLegend();
      }
      _fire !== false && fire("setCursor");
    }
    let rect2 = null;
    Object.defineProperty(self, "rect", {
      get() {
        if (rect2 == null)
          syncRect(false);
        return rect2;
      }
    });
    function syncRect(defer = false) {
      if (defer)
        rect2 = null;
      else {
        rect2 = over.getBoundingClientRect();
        fire("syncRect", rect2);
      }
    }
    function mouseMove(e, src, _l, _t, _w, _h, _i) {
      if (cursor._lock)
        return;
      if (dragging && e != null && e.movementX == 0 && e.movementY == 0)
        return;
      cacheMouse(e, src, _l, _t, _w, _h, _i, false, e != null);
      if (e != null)
        updateCursor(null, true, true);
      else
        updateCursor(src, true, false);
    }
    function cacheMouse(e, src, _l, _t, _w, _h, _i, initial, snap) {
      if (rect2 == null)
        syncRect(false);
      setCursorEvent(e);
      if (e != null) {
        _l = e.clientX - rect2.left;
        _t = e.clientY - rect2.top;
      } else {
        if (_l < 0 || _t < 0) {
          mouseLeft1 = -10;
          mouseTop1 = -10;
          return;
        }
        let [xKey, yKey] = syncOpts.scales;
        let syncOptsSrc = src.cursor.sync;
        let [xValSrc, yValSrc] = syncOptsSrc.values;
        let [xKeySrc, yKeySrc] = syncOptsSrc.scales;
        let [matchXKeys, matchYKeys] = syncOpts.match;
        let rotSrc = src.axes[0].side % 2 == 1;
        let xDim = scaleX.ori == 0 ? plotWidCss : plotHgtCss, yDim = scaleX.ori == 1 ? plotWidCss : plotHgtCss, _xDim = rotSrc ? _h : _w, _yDim = rotSrc ? _w : _h, _xPos = rotSrc ? _t : _l, _yPos = rotSrc ? _l : _t;
        if (xKeySrc != null)
          _l = matchXKeys(xKey, xKeySrc) ? getPos(xValSrc, scales[xKey], xDim, 0) : -10;
        else
          _l = xDim * (_xPos / _xDim);
        if (yKeySrc != null)
          _t = matchYKeys(yKey, yKeySrc) ? getPos(yValSrc, scales[yKey], yDim, 0) : -10;
        else
          _t = yDim * (_yPos / _yDim);
        if (scaleX.ori == 1) {
          let __l = _l;
          _l = _t;
          _t = __l;
        }
      }
      if (snap && (src == null || src.cursor.event.type == mousemove)) {
        if (_l <= 1 || _l >= plotWidCss - 1)
          _l = incrRound(_l, plotWidCss);
        if (_t <= 1 || _t >= plotHgtCss - 1)
          _t = incrRound(_t, plotHgtCss);
      }
      if (initial) {
        rawMouseLeft0 = _l;
        rawMouseTop0 = _t;
        [mouseLeft0, mouseTop0] = cursor.move(self, _l, _t);
      } else {
        mouseLeft1 = _l;
        mouseTop1 = _t;
      }
    }
    const _hideProps = {
      width: 0,
      height: 0,
      left: 0,
      top: 0
    };
    function hideSelect() {
      setSelect(_hideProps, false);
    }
    let downSelectLeft;
    let downSelectTop;
    let downSelectWidth;
    let downSelectHeight;
    function mouseDown(e, src, _l, _t, _w, _h, _i) {
      dragging = true;
      dragX = dragY = drag._x = drag._y = false;
      cacheMouse(e, src, _l, _t, _w, _h, _i, true, false);
      if (e != null) {
        onMouse(mouseup, doc, mouseUp, false);
        pubSync(mousedown, self, mouseLeft0, mouseTop0, plotWidCss, plotHgtCss, null);
      }
      let { left, top, width, height } = select;
      downSelectLeft = left;
      downSelectTop = top;
      downSelectWidth = width;
      downSelectHeight = height;
    }
    function mouseUp(e, src, _l, _t, _w, _h, _i) {
      dragging = drag._x = drag._y = false;
      cacheMouse(e, src, _l, _t, _w, _h, _i, false, true);
      let { left, top, width, height } = select;
      let hasSelect = width > 0 || height > 0;
      let chgSelect = downSelectLeft != left || downSelectTop != top || downSelectWidth != width || downSelectHeight != height;
      hasSelect && chgSelect && setSelect(select);
      if (drag.setScale && hasSelect && chgSelect) {
        let xOff = left, xDim = width, yOff = top, yDim = height;
        if (scaleX.ori == 1) {
          xOff = top, xDim = height, yOff = left, yDim = width;
        }
        if (dragX) {
          _setScale(
            xScaleKey,
            posToVal(xOff, xScaleKey),
            posToVal(xOff + xDim, xScaleKey)
          );
        }
        if (dragY) {
          for (let k in scales) {
            let sc = scales[k];
            if (k != xScaleKey && sc.from == null && sc.min != inf) {
              _setScale(
                k,
                posToVal(yOff + yDim, k),
                posToVal(yOff, k)
              );
            }
          }
        }
        hideSelect();
      } else if (cursor.lock) {
        cursor._lock = !cursor._lock;
        updateCursor(src, true, e != null);
      }
      if (e != null) {
        offMouse(mouseup, doc);
        pubSync(mouseup, self, mouseLeft1, mouseTop1, plotWidCss, plotHgtCss, null);
      }
    }
    function mouseLeave(e, src, _l, _t, _w, _h, _i) {
      if (cursor._lock)
        return;
      setCursorEvent(e);
      let _dragging = dragging;
      if (dragging) {
        let snapH = true;
        let snapV = true;
        let snapProx = 10;
        let dragH, dragV;
        if (scaleX.ori == 0) {
          dragH = dragX;
          dragV = dragY;
        } else {
          dragH = dragY;
          dragV = dragX;
        }
        if (dragH && dragV) {
          snapH = mouseLeft1 <= snapProx || mouseLeft1 >= plotWidCss - snapProx;
          snapV = mouseTop1 <= snapProx || mouseTop1 >= plotHgtCss - snapProx;
        }
        if (dragH && snapH)
          mouseLeft1 = mouseLeft1 < mouseLeft0 ? 0 : plotWidCss;
        if (dragV && snapV)
          mouseTop1 = mouseTop1 < mouseTop0 ? 0 : plotHgtCss;
        updateCursor(null, true, true);
        dragging = false;
      }
      mouseLeft1 = -10;
      mouseTop1 = -10;
      activeIdxs.fill(null);
      updateCursor(null, true, true);
      if (_dragging)
        dragging = _dragging;
    }
    function dblClick(e, src, _l, _t, _w, _h, _i) {
      if (cursor._lock)
        return;
      setCursorEvent(e);
      autoScaleX();
      hideSelect();
      if (e != null)
        pubSync(dblclick, self, mouseLeft1, mouseTop1, plotWidCss, plotHgtCss, null);
    }
    function syncPxRatio() {
      axes.forEach(syncFontSize);
      _setSize(self.width, self.height, true);
    }
    on(dppxchange, win, syncPxRatio);
    const events = {};
    events.mousedown = mouseDown;
    events.mousemove = mouseMove;
    events.mouseup = mouseUp;
    events.dblclick = dblClick;
    events["setSeries"] = (e, src, idx, opts2) => {
      let seriesIdxMatcher2 = syncOpts.match[2];
      idx = seriesIdxMatcher2(self, src, idx);
      idx != -1 && setSeries(idx, opts2, true, false);
    };
    if (showCursor) {
      onMouse(mousedown, over, mouseDown);
      onMouse(mousemove, over, mouseMove);
      onMouse(mouseenter, over, (e) => {
        setCursorEvent(e);
        syncRect(false);
      });
      onMouse(mouseleave, over, mouseLeave);
      onMouse(dblclick, over, dblClick);
      cursorPlots.add(self);
      self.syncRect = syncRect;
    }
    const hooks = self.hooks = opts.hooks || {};
    function fire(evName, a1, a2) {
      if (deferHooks)
        hooksQueue.push([evName, a1, a2]);
      else {
        if (evName in hooks) {
          hooks[evName].forEach((fn) => {
            fn.call(null, self, a1, a2);
          });
        }
      }
    }
    (opts.plugins || []).forEach((p) => {
      for (let evName in p.hooks)
        hooks[evName] = (hooks[evName] || []).concat(p.hooks[evName]);
    });
    const seriesIdxMatcher = (self2, src, srcSeriesIdx) => srcSeriesIdx;
    const syncOpts = assign({
      key: null,
      setSeries: false,
      filters: {
        pub: retTrue,
        sub: retTrue
      },
      scales: [xScaleKey, series[1] ? series[1].scale : null],
      match: [retEq, retEq, seriesIdxMatcher],
      values: [null, null]
    }, cursor.sync);
    if (syncOpts.match.length == 2)
      syncOpts.match.push(seriesIdxMatcher);
    cursor.sync = syncOpts;
    const syncKey = syncOpts.key;
    const sync = _sync(syncKey);
    function pubSync(type, src, x, y, w, h, i) {
      if (syncOpts.filters.pub(type, src, x, y, w, h, i))
        sync.pub(type, src, x, y, w, h, i);
    }
    sync.sub(self);
    function pub(type, src, x, y, w, h, i) {
      if (syncOpts.filters.sub(type, src, x, y, w, h, i))
        events[type](null, src, x, y, w, h, i);
    }
    self.pub = pub;
    function destroy() {
      sync.unsub(self);
      cursorPlots.delete(self);
      mouseListeners.clear();
      off(dppxchange, win, syncPxRatio);
      root.remove();
      legendTable?.remove();
      fire("destroy");
    }
    self.destroy = destroy;
    function _init() {
      fire("init", opts, data);
      setData(data || opts.data, false);
      if (pendScales[xScaleKey])
        setScale(xScaleKey, pendScales[xScaleKey]);
      else
        autoScaleX();
      shouldSetSelect = select.show && (select.width > 0 || select.height > 0);
      shouldSetCursor = shouldSetLegend = true;
      _setSize(opts.width, opts.height);
    }
    series.forEach(initSeries);
    axes.forEach(initAxis);
    if (then) {
      if (then instanceof HTMLElement) {
        then.appendChild(root);
        _init();
      } else
        then(self, _init);
    } else
      _init();
    return self;
  }
  uPlot.assign = assign;
  uPlot.fmtNum = fmtNum;
  uPlot.rangeNum = rangeNum;
  uPlot.rangeLog = rangeLog;
  uPlot.rangeAsinh = rangeAsinh;
  uPlot.orient = orient;
  uPlot.pxRatio = pxRatio;
  {
    uPlot.join = join;
  }
  {
    uPlot.fmtDate = fmtDate;
    uPlot.tzDate = tzDate;
  }
  uPlot.sync = _sync;
  {
    uPlot.addGap = addGap;
    uPlot.clipGaps = clipGaps;
    let paths = uPlot.paths = {
      points
    };
    paths.linear = linear;
    paths.stepped = stepped;
    paths.bars = bars;
    paths.spline = monotoneCubic;
  }

  // web/src/components/shared/LiveCurve/chartData.ts
  init_define_import_meta_env();

  // web/src/components/shared/LiveCurve/types.ts
  init_define_import_meta_env();
  var SERIES_KEYS = ["bean", "env", "ror", "heat", "fan"];

  // web/src/components/shared/LiveCurve/chartData.ts
  function toColumns(points2) {
    const x = [];
    const cols = {
      bean: [],
      env: [],
      ror: [],
      heat: [],
      fan: []
    };
    for (const p of points2) {
      x.push(p.t);
      for (const key of SERIES_KEYS) {
        cols[key].push(p[key]);
      }
    }
    return [x, cols.bean, cols.env, cols.ror, cols.heat, cols.fan];
  }
  function formatElapsed(seconds) {
    if (seconds === null || !Number.isFinite(seconds) || seconds < 0) return "\u2014";
    const total = Math.round(seconds);
    const mins = Math.floor(total / 60);
    const secs = total % 60;
    return `${mins}:${secs.toString().padStart(2, "0")}`;
  }
  function formatRoastTime(seconds, origin) {
    if (seconds === null || !Number.isFinite(seconds)) return "\u2014";
    if (origin === null || !Number.isFinite(origin)) return formatElapsed(seconds);
    const d = Math.round(seconds) - Math.round(origin);
    const mins = Math.floor(Math.abs(d) / 60);
    const secs = Math.abs(d) % 60;
    const body = `${mins}:${secs.toString().padStart(2, "0")}`;
    return d < 0 ? `-${body}` : body;
  }
  function formatSeriesValue(key, value) {
    if (value === null || Number.isNaN(value)) return "\u2014";
    switch (key) {
      case "bean":
      case "env":
        return `${value.toFixed(1)} \xB0C`;
      case "ror":
        return `${value.toFixed(1)} \xB0C/min`;
      case "heat":
      case "fan":
        return `${Math.round(value)} %`;
    }
  }

  // web/src/components/shared/LiveCurve/scales.ts
  init_define_import_meta_env();
  var SCALE_COLUMNS = {
    x: [0],
    c: [1, 2],
    // bean + env feed the °C axis (auto-ranged, #307) — LOGICAL indices
    ror: [3]
    // doc-only: RoR column feeds the RoR axis (FIXED range — not data-driven)
  };
  var FIXED_SCALE_RANGES = {
    ror: [-20, 30]
  };
  var TEMP_RANGE = {
    PAD: 8,
    QUANTUM: 10,
    MIN_SPAN: 40,
    FLOOR: 0
  };
  function floorTo(v, q) {
    return Math.floor(v / q) * q;
  }
  function ceilTo(v, q) {
    return Math.ceil(v / q) * q;
  }
  function computeTempRange(dataLo, dataHi, prev) {
    const { PAD, QUANTUM, MIN_SPAN, FLOOR } = TEMP_RANGE;
    if (dataLo === null || dataHi === null) {
      return prev ?? [FLOOR, FLOOR + Math.max(MIN_SPAN, 2 * PAD + QUANTUM)];
    }
    let targetLo = floorTo(Math.max(FLOOR, dataLo - PAD), QUANTUM);
    let targetHi = ceilTo(dataHi + PAD, QUANTUM);
    if (targetHi - targetLo < MIN_SPAN) {
      const mid = (dataLo + dataHi) / 2;
      targetLo = floorTo(Math.max(FLOOR, mid - MIN_SPAN / 2), QUANTUM);
      targetHi = ceilTo(targetLo + MIN_SPAN, QUANTUM);
    }
    if (prev === null || prev[0] === null || prev[1] === null) return [targetLo, targetHi];
    const prevLo = prev[0];
    const prevHi = prev[1];
    const slack = QUANTUM;
    const paddedLo = dataLo - PAD;
    const paddedHi = dataHi + PAD;
    let nextLo = prevLo;
    let nextHi = prevHi;
    if (paddedLo < prevLo) nextLo = Math.min(prevLo, targetLo);
    else if (paddedLo > prevLo + slack) nextLo = targetLo;
    if (paddedHi > prevHi) nextHi = Math.max(prevHi, targetHi);
    else if (paddedHi < prevHi - slack) nextHi = targetHi;
    nextLo = Math.min(nextLo, targetLo);
    nextHi = Math.max(nextHi, targetHi);
    if (nextHi - nextLo < MIN_SPAN) return [targetLo, targetHi];
    return [nextLo, nextHi];
  }
  function dataExtent(columns, indices) {
    let lo = Infinity;
    let hi = -Infinity;
    for (const ci of indices) {
      const series = columns[ci];
      if (!series) continue;
      for (const v of series) {
        if (v == null || !Number.isFinite(v)) continue;
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
    }
    return { lo, hi, hasData: lo !== Infinity && hi !== -Infinity };
  }
  function makeAutoRange(getChargeBand, state, getLogicalColumns) {
    return (_self, _min, _max, scaleKey) => {
      const fixed = FIXED_SCALE_RANGES[scaleKey];
      if (fixed) return fixed;
      const cols = SCALE_COLUMNS[scaleKey] ?? [];
      const { lo, hi, hasData: hasData2 } = dataExtent(getLogicalColumns(), cols);
      if (scaleKey === "c") {
        let lo2 = lo;
        let hi2 = hi;
        let has = hasData2;
        const band = getChargeBand();
        if (band.visible) {
          lo2 = has ? Math.min(lo2, band.minC) : band.minC;
          hi2 = has ? Math.max(hi2, band.maxC) : band.maxC;
          has = true;
        }
        const next = computeTempRange(has ? lo2 : null, has ? hi2 : null, state.tempRange);
        state.tempRange = next;
        return next;
      }
      if (!hasData2) return [_min, _max];
      if (lo === hi) return [lo - 1, hi + 1];
      return [lo, hi];
    };
  }

  // web/src/components/shared/LiveCurve/LiveCurve.tsx
  var MARKER_RGB = {
    t0: "212, 212, 216",
    // neutral grey (unchanged from pre-#309)
    dry_end: "161, 161, 170",
    // muted zinc — a minor landmark (#351), see DRY_END_ALPHA
    first_crack: "251, 191, 36",
    // amber — the crack landmark
    drop: "248, 113, 113",
    // red — beans out
    cooling: "96, 165, 250"
    // blue — cooling air
  };
  var DRY_END_ALPHA = { line: 0.32, label: 0.55 };
  function markerColor(kind, alpha) {
    return `rgba(${MARKER_RGB[kind]}, ${alpha})`;
  }
  var DEFAULT_CHARGE_BAND = { minC: 170, maxC: 200 };
  function token(name, fallback) {
    if (typeof window === "undefined") return fallback;
    const v = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return v || fallback;
  }
  function seriesMeta() {
    return [
      { key: "bean", label: "Bean", scale: "c", stroke: token("--roast-coffee", "#d97706"), step: false, width: 2, z: 4 },
      { key: "env", label: "Env", scale: "c", stroke: token("--muted-foreground", "#d4d4d8"), step: false, width: 2, z: 3 },
      { key: "ror", label: "RoR", scale: "ror", stroke: token("--roast-nominal", "#34d399"), step: false, width: 2, z: 2 },
      { key: "heat", label: "Heat", scale: "pct", stroke: token("--roast-heat", "#fbbf24"), step: true, width: 1.25, dash: [4, 3], z: 0 },
      { key: "fan", label: "Fan", scale: "pct", stroke: token("--roast-fan", "#22d3ee"), step: true, width: 1.25, dash: [4, 3], z: 1 }
    ];
  }
  function plotDrawOrder(meta) {
    return meta.map((_2, i) => i).sort((a, b) => meta[a].z - meta[b].z);
  }
  function toPlotData(columns, order) {
    const [x, ...seriesCols] = columns;
    return [x, ...order.map((logicalIdx) => seriesCols[logicalIdx])];
  }
  function LiveCurve({
    points: points2,
    markers = [],
    phase = null,
    chargeBand = DEFAULT_CHARGE_BAND,
    highlightTime = null,
    originSeconds = null,
    initialHidden = [],
    className,
    height = 420
  }) {
    const hostRef = (0, import_react.useRef)(null);
    const plotRef = (0, import_react.useRef)(null);
    const meta = (0, import_react.useMemo)(seriesMeta, []);
    const [visible, setVisible] = (0, import_react.useState)(() => {
      const base = {
        bean: true,
        env: true,
        ror: true,
        heat: true,
        fan: true
      };
      for (const key of initialHidden) base[key] = false;
      return base;
    });
    const [cursorIdx, setCursorIdx] = (0, import_react.useState)(null);
    const columns = (0, import_react.useMemo)(() => toColumns(points2), [points2]);
    const chargeBandVisible = phase === "preheating";
    const drawOrder = (0, import_react.useMemo)(() => plotDrawOrder(meta), [meta]);
    const autoRangeRef = (0, import_react.useRef)({ tempRange: null });
    const overlayRef = (0, import_react.useRef)({ markers, highlightTime, chargeBandVisible, chargeBand });
    overlayRef.current = { markers, highlightTime, chargeBandVisible, chargeBand };
    const originRef = (0, import_react.useRef)(originSeconds);
    originRef.current = originSeconds;
    const columnsRef = (0, import_react.useRef)(columns);
    columnsRef.current = columns;
    (0, import_react.useEffect)(() => {
      const host = hostRef.current;
      if (!host) return;
      const rangeFn = makeAutoRange(
        () => ({
          visible: overlayRef.current.chargeBandVisible,
          minC: overlayRef.current.chargeBand.minC,
          maxC: overlayRef.current.chargeBand.maxC
        }),
        autoRangeRef.current,
        () => columnsRef.current
      );
      const opts = {
        width: host.clientWidth || 800,
        height,
        // Cursor drives the legend readout; we mirror the hovered index to state.
        cursor: {
          focus: { prox: 16 },
          sync: { key: "roast" }
        },
        legend: { show: false },
        // we render our own legend (readout + toggle)
        scales: {
          // `rangeFn` policy per scale: x (time) re-ranges to the loaded data; c
          // (temperature) is controlled-dynamic auto-range with hysteresis (#307); ror
          // is FIXED (−20..+30, comparable across roasts).
          // The plot is built once (on [height, meta]) while the dashboard's live series
          // is still EMPTY (it mounts before SSE frames arrive), so uPlot leaves x
          // unranged — {min:null,max:null}, which collapsed the series to a single point
          // at index 0 (invisible). `setData` was not re-ranging it; the explicit `range`
          // callback recomputes x's min/max from the data uPlot is about to draw, so x
          // always covers the loaded elapsed-time range.
          // A `range` callback fires unconditionally, so `auto` has no effect and is
          // omitted (#133).
          x: { time: false, range: rangeFn },
          c: { range: rangeFn },
          ror: { range: rangeFn },
          // Dedicated FIXED 0–100 % scale for the control lines (#307) — its own axis
          // (below), so heat/fan read as percentages and never ride the temp/RoR scale.
          pct: { range: [0, 100] }
        },
        axes: [
          {
            stroke: token("--muted-foreground", "#a1a1aa"),
            grid: { show: true, stroke: token("--border", "#3f3f46") },
            // The x is SERVE-elapsed SECONDS; render the tick labels as CHARGE-
            // referenced ROAST TIME (#326) — 0:00 = charge, negative in preheat —
            // via `formatRoastTime(v, origin)`. Before T0 lands (origin null) this
            // falls back to serve-elapsed M:SS (#153). Display-only; the data stays
            // serve seconds. `time:false` on the x scale, so uPlot passes raw
            // numeric splits here.
            values: (_self, splits) => splits.map((v) => formatRoastTime(v, originRef.current))
          },
          { scale: "c", stroke: token("--muted-foreground", "#a1a1aa"), grid: { show: false } },
          { scale: "ror", side: 1, stroke: token("--roast-nominal", "#34d399"), grid: { show: false } },
          // Dedicated 0–100 % axis for the control lines (#307), drawn SUBTLY on the
          // right (below the RoR axis) so heat/fan read as their own % scale without
          // competing with the measurement axes: muted stroke, ticks every 25 %, no grid.
          {
            scale: "pct",
            side: 1,
            stroke: token("--muted-foreground", "#71717a"),
            grid: { show: false },
            ticks: { show: false },
            size: 34,
            splits: [0, 25, 50, 75, 100],
            values: (_self, splits) => splits.map((v) => `${v}%`),
            font: "10px ui-sans-serif, system-ui, sans-serif"
          }
        ],
        // Series + data are handed to uPlot in PLOT (draw) order (#307) so the control
        // lines paint BEHIND bean/env/RoR; the public `columns`/test-hook stay logical.
        series: [
          {},
          ...drawOrder.map((logicalIdx) => {
            const m = meta[logicalIdx];
            return {
              label: m.label,
              scale: m.scale,
              stroke: m.stroke,
              width: m.width,
              dash: m.dash,
              paths: m.step ? uPlot.paths.stepped?.({ align: 1 }) : void 0,
              show: visible[m.key],
              points: { show: false }
            };
          })
        ],
        hooks: {
          setCursor: [
            (u) => {
              setCursorIdx(u.cursor.idx ?? null);
            }
          ],
          draw: [
            (u) => {
              const o = overlayRef.current;
              drawOverlays(u, o.markers, o.highlightTime, o.chargeBandVisible, o.chargeBand);
            }
          ]
        }
      };
      const plot = new uPlot(opts, toPlotData(columns, drawOrder), host);
      plotRef.current = plot;
      const onResize = () => plot.setSize({ width: host.clientWidth || 800, height });
      window.addEventListener("resize", onResize);
      return () => {
        window.removeEventListener("resize", onResize);
        plot.destroy();
        plotRef.current = null;
      };
    }, [height, meta]);
    (0, import_react.useEffect)(() => {
      plotRef.current?.setData(toPlotData(columns, drawOrder));
    }, [columns, drawOrder]);
    (0, import_react.useEffect)(() => {
      const plot = plotRef.current;
      if (!plot) return;
      drawOrder.forEach(
        (logicalIdx, k) => plot.setSeries(k + 1, { show: visible[meta[logicalIdx].key] })
      );
    }, [visible, meta, drawOrder]);
    (0, import_react.useEffect)(() => {
      plotRef.current?.redraw();
    }, [markers, highlightTime]);
    (0, import_react.useEffect)(() => {
      plotRef.current?.redraw();
    }, [originSeconds]);
    (0, import_react.useEffect)(() => {
      plotRef.current?.redraw();
    }, [chargeBandVisible, chargeBand]);
    (0, import_react.useEffect)(() => {
      const plot = plotRef.current;
      const sx = plot?.scales.x;
      const sror = plot?.scales.ror;
      const spct = plot?.scales.pct;
      const tc = autoRangeRef.current.tempRange;
      const hook = {
        columns,
        visible,
        markers,
        highlightTime,
        chargeBandVisible,
        scales: {
          x: { min: sx?.min ?? null, max: sx?.max ?? null },
          // °C from the auto-range source of truth, not the possibly-stale uPlot scale.
          c: { min: tc?.[0] ?? null, max: tc?.[1] ?? null },
          ror: { min: sror?.min ?? null, max: sror?.max ?? null },
          pct: { min: spct?.min ?? null, max: spct?.max ?? null }
        }
      };
      if (typeof window !== "undefined") window.__chart = hook;
    }, [columns, visible, markers, highlightTime, chargeBandVisible]);
    const toggle = (key) => setVisible((prev) => ({ ...prev, [key]: !prev[key] }));
    const readoutIdx = cursorIdx ?? (points2.length > 0 ? points2.length - 1 : null);
    const readoutPoint = readoutIdx === null ? null : points2[readoutIdx] ?? null;
    return /* @__PURE__ */ React.createElement("div", { className: cn("flex flex-col gap-2", className), "data-testid": "live-curve" }, /* @__PURE__ */ React.createElement(
      Legend,
      {
        meta,
        visible,
        readout: readoutPoint,
        readoutTime: readoutPoint?.t ?? null,
        originSeconds,
        onToggle: toggle
      }
    ), /* @__PURE__ */ React.createElement(
      "div",
      {
        ref: hostRef,
        "data-chart-ready": "true",
        "data-charge-band": chargeBandVisible ? "true" : "false",
        "data-marker-count": markers.length,
        "data-highlight": highlightTime ?? "",
        className: "w-full",
        style: { height }
      }
    ));
  }
  function Legend({ meta, visible, readout, readoutTime, originSeconds, onToggle }) {
    return /* @__PURE__ */ React.createElement("div", { className: "flex flex-wrap items-center gap-x-4 gap-y-1 text-xs", "data-testid": "live-curve-legend" }, /* @__PURE__ */ React.createElement("span", { className: "numeric font-medium text-muted-foreground", "data-testid": "legend-time" }, formatRoastTime(readoutTime, originSeconds)), meta.map((m) => {
      const value = readout ? readout[m.key] : null;
      return /* @__PURE__ */ React.createElement(
        "button",
        {
          key: m.key,
          type: "button",
          "data-testid": `legend-${m.key}`,
          "data-series": m.key,
          "data-visible": visible[m.key] ? "true" : "false",
          "aria-pressed": visible[m.key],
          onClick: () => onToggle(m.key),
          className: cn(
            "inline-flex items-center gap-1.5 rounded px-1 py-0.5 transition-opacity",
            visible[m.key] ? "opacity-100" : "opacity-40"
          )
        },
        /* @__PURE__ */ React.createElement("span", { className: "size-2 rounded-sm", style: { background: m.stroke }, "aria-hidden": true }),
        /* @__PURE__ */ React.createElement("span", { className: "font-medium" }, m.label),
        /* @__PURE__ */ React.createElement("span", { className: "numeric text-muted-foreground" }, formatSeriesValue(m.key, value))
      );
    }));
  }
  function drawOverlays(u, markers, highlightTime, chargeBandVisible, chargeBand) {
    const ctx = u.ctx;
    ctx.save();
    if (chargeBandVisible) {
      const yTop = u.valToPos(chargeBand.maxC, "c", true);
      const yBot = u.valToPos(chargeBand.minC, "c", true);
      ctx.fillStyle = "rgba(148, 163, 184, 0.12)";
      ctx.fillRect(u.bbox.left, yTop, u.bbox.width, yBot - yTop);
    }
    const LABEL_CLUSTER_PX = 48;
    const LABEL_ROW_PX = 12;
    const ordered = [...markers].sort((a, b) => a.t - b.t);
    ctx.font = "10px ui-sans-serif, system-ui, sans-serif";
    ctx.textBaseline = "top";
    ctx.textAlign = "left";
    let prevLabelX = null;
    let labelRow = 0;
    for (const marker of ordered) {
      const x = u.valToPos(marker.t, "x", true);
      const isDryEnd = marker.kind === "dry_end";
      const lineAlpha = isDryEnd ? DRY_END_ALPHA.line : 0.6;
      const labelAlpha = isDryEnd ? DRY_END_ALPHA.label : 0.9;
      ctx.strokeStyle = markerColor(marker.kind, lineAlpha);
      ctx.lineWidth = 1;
      ctx.setLineDash(isDryEnd ? [3, 4] : []);
      line(ctx, x, u.bbox.top, x, u.bbox.top + u.bbox.height);
      ctx.setLineDash([]);
      if (prevLabelX !== null && x - prevLabelX < LABEL_CLUSTER_PX) {
        labelRow += 1;
      } else {
        labelRow = 0;
      }
      prevLabelX = x;
      ctx.fillStyle = markerColor(marker.kind, labelAlpha);
      ctx.fillText(marker.label, x + 3, u.bbox.top + 2 + labelRow * LABEL_ROW_PX);
    }
    if (highlightTime !== null) {
      const x = u.valToPos(highlightTime, "x", true);
      ctx.strokeStyle = "#ffffff";
      ctx.lineWidth = 2;
      line(ctx, x, u.bbox.top, x, u.bbox.top + u.bbox.height);
    }
    ctx.restore();
  }
  function line(ctx, x0, y0, x1, y1) {
    ctx.beginPath();
    ctx.moveTo(x0, y0);
    ctx.lineTo(x1, y1);
    ctx.stroke();
  }
  return __toCommonJS(ds_entry_exports);
})();
window.RoastPilotDS=RoastPilotDS.__dsMainNs?Object.assign({},RoastPilotDS,RoastPilotDS.__dsMainNs,{__dsMainNs:undefined}):RoastPilotDS;
