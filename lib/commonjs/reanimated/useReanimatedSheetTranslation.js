"use strict";

Object.defineProperty(exports, "__esModule", {
  value: true
});
exports.default = useReanimatedSheetTranslation;
var React = _interopRequireWildcard(require("react"));
var _ReanimatedSheetTranslationContext = _interopRequireDefault(require("./ReanimatedSheetTranslationContext"));
function _interopRequireDefault(e) { return e && e.__esModule ? e : { default: e }; }
function _getRequireWildcardCache(e) { if ("function" != typeof WeakMap) return null; var r = new WeakMap(), t = new WeakMap(); return (_getRequireWildcardCache = function (e) { return e ? t : r; })(e); }
function _interopRequireWildcard(e, r) { if (!r && e && e.__esModule) return e; if (null === e || "object" != typeof e && "function" != typeof e) return { default: e }; var t = _getRequireWildcardCache(r); if (t && t.has(e)) return t.get(e); var n = { __proto__: null }, a = Object.defineProperty && Object.getOwnPropertyDescriptor; for (var u in e) if ("default" !== u && {}.hasOwnProperty.call(e, u)) { var i = a ? Object.getOwnPropertyDescriptor(e, u) : null; i && (i.get || i.set) ? Object.defineProperty(n, u, i) : n[u] = e[u]; } return n.default = e, t && t.set(e, n), n; }
function useReanimatedSheetTranslation() {
  const translation = React.useContext(_ReanimatedSheetTranslationContext.default);
  if (translation === undefined) {
    throw new Error("Couldn't find values for reanimated sheet translation. Are you inside a screen in Native Stack?");
  }
  return translation;
}
//# sourceMappingURL=useReanimatedSheetTranslation.js.map