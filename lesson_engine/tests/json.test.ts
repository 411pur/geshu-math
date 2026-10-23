import { describe, expect, it } from 'vitest';
import { extractJsonObject, normalizeJsonText, repairLooseJson, safeJsonForScript } from '../src/lib/json.js';

describe('model JSON parsing', () => {
  it('extracts JSON from a markdown code fence', () => {
    const parsed = extractJsonObject('说明文字\n```json\n{"answer":"A"}\n```');
    expect(parsed).toEqual({ answer: 'A' });
  });

  it('extracts JSON from surrounding prose', () => {
    const parsed = extractJsonObject('结果如下： {"ok": true} 请查收');
    expect(parsed).toEqual({ ok: true });
  });

  it('escapes HTML-sensitive characters for an inline script', () => {
    const value = safeJsonForScript({ text: '</script><script>alert(1)</script>' });
    expect(value).not.toContain('</script>');
    expect(value).toContain('\\u003c/script\\u003e');
  });
});

describe('normalizeJsonText（国产大模型全角标点清洗）', () => {
  it('全角引号替换为半角', () => {
    const out = normalizeJsonText('{"difficulty"：“中等”}');
    expect(out).toBe('{"difficulty":"中等"}');
  });

  it('中文冒号键值分隔替换为半角', () => {
    const out = normalizeJsonText('{"key"："value", "a"："b"}');
    expect(out).toBe('{"key":"value", "a":"b"}');
  });

  it('值内部的中文冒号/逗号不被误伤（保持在字符串内）', () => {
    const out = normalizeJsonText('{"tip":"注意：这里用中文逗号，保留"}');
    expect(out).toBe('{"tip":"注意：这里用中文逗号，保留"}');
  });

  it('中文冒号前不是引号的场合不被替换（"a："在值内部）', () => {
    const out = normalizeJsonText('{"text":"公式：F=ma"}');
    expect(out).toBe('{"text":"公式：F=ma"}');
  });

  it('数组元素后的中文逗号替换为半角', () => {
    const out = normalizeJsonText('{"arr":["a"，“b"],"n":1}');
    expect(out).toBe('{"arr":["a","b"],"n":1}');
  });

  it('全角引号+中文冒号+中文逗号混合的完整场景可通过 JSON.parse', () => {
    const raw =
      '{"title"：“五块砖的静摩擦力分析”，“problem":{"stem”:"如图甲”，“options”:[{"key"：“A”,"text”："砖夹压力"}],“answer”：“B”} }';
    expect(() => JSON.parse(normalizeJsonText(raw))).not.toThrow();
  });
});

describe('宽松 JSON 修复（模型写法污染）', () => {
  it('字符串里出现未转义的双引号也能解析出来', () => {
    const raw = '{"ok":false,"issues":["图形画错：a 棒长应为 3L，图中"rod-a"不够长"]}';
    const parsed = extractJsonObject(raw) as { ok: boolean; issues: string[] };
    expect(parsed.ok).toBe(false);
    expect(parsed.issues[0]).toContain('"rod-a"');
    expect(parsed.issues[0]).toContain('不够长');
  });

  it('字符串里的裸换行会被转义而不是丢掉内容', () => {
    const raw = '{"note":"第一行\n第二行"}';
    expect((extractJsonObject(raw) as { note: string }).note).toBe('第一行\n第二行');
  });

  it('本来就合法的 JSON 不受影响', () => {
    // 用 String.raw 才能表达"已经是合法 JSON 的转义引号"（普通字符串字面量里 \" 会变成裸引号）
    const raw = String.raw`{"a":[1,2],"b":{"c":"d"},"e":"引号 \" 已转义"}`;
    expect(repairLooseJson(raw)).toBe(raw);
    expect(extractJsonObject(raw)).toEqual({ a: [1, 2], b: { c: 'd' }, e: '引号 " 已转义' });
  });

  it('全角标点与内部引号同时出现也能救回来', () => {
    const raw = '{"ok"：false，"issues"：["图中"b 棒"位置不对"]}';
    const parsed = extractJsonObject(raw) as { ok: boolean; issues: string[] };
    expect(parsed.ok).toBe(false);
    expect(parsed.issues[0]).toContain('b 棒');
  });
});
