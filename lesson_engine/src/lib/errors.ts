export class AppError extends Error {
  readonly code: string;
  readonly statusCode: number;

  constructor(code: string, message: string, statusCode = 500) {
    super(message);
    this.name = 'AppError';
    this.code = code;
    this.statusCode = statusCode;
  }
}

export class ConfigurationError extends AppError {
  constructor(message: string) {
    super('configuration_error', message, 503);
    this.name = 'ConfigurationError';
  }
}

export class ProviderError extends AppError {
  readonly provider: string;

  constructor(provider: string, message: string, statusCode = 502) {
    super('provider_error', message, statusCode);
    this.name = 'ProviderError';
    this.provider = provider;
  }
}

/**
 * 模型把输出预算全部花在大段思考上：响应里 reasoning_content 很长、content 为空、
 * finish_reason=length。这种情况原样重试没有意义（下次还是会烧光预算），
 * 调用方应当改写请求——例如关掉 thinking 让它直接产出 JSON。
 */
export class ReasoningBudgetError extends ProviderError {
  readonly reasoningLength: number;

  constructor(provider: string, message: string, reasoningLength = 0) {
    super(provider, message, 502);
    this.name = 'ReasoningBudgetError';
    this.reasoningLength = reasoningLength;
  }
}

export function redactSecret(value?: string): string {
  if (!value) return '<missing>';
  if (value.length <= 8) return '***';
  return `${value.slice(0, 4)}***${value.slice(-4)}`;
}
