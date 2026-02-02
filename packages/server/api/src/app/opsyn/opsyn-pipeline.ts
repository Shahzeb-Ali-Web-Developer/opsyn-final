/**
 * OPSYN Unified Pipeline
 *
 * Safe, build-stable pipeline for AI → FlowTemplate conversion.
 * No schema mutation, no heavy processors, no side effects.
 */

import { Flow } from '../flows/flow-post-processor';

/**
 * System prompt for the AI model
 */
export const OPSYN_SYSTEM_PROMPT =
  'You are an AI Workflow Builder for OPSYN (Activepieces-based). ' +
  'Return ONLY a valid JSON object with keys: displayName, trigger, schemaVersion. No extra text.';

/**
 * Extended system prompt with more guidance
 */
export const OPSYN_SYSTEM_PROMPT_EXTENDED = `You are an AI Workflow Builder for OPSYN (Activepieces-based).

CRITICAL RULES:
1. Return ONLY valid JSON with keys: displayName, trigger, schemaVersion
2. Include ALL steps mentioned in the instruction
3. For conditionals (if/then/else), use ROUTER action with branches
4. Always include: trigger.settings.pieceVersion, trigger.settings.propertySettings
5. Never include: inputUiInfo, pieceType, or other UI-only fields
6. triggerName goes INSIDE settings.triggerName, not at trigger level

Return ONLY the JSON object. No markdown, no extra text.`;

/**
 * FlowTemplate format for UI import
 */
export interface FlowTemplate {
  name: string;
  description: string;
  tags: string[];
  pieces: string[];
  template: Flow;
  blogUrl?: string;
}

/**
 * Extract JSON from raw model output
 */
function extractJsonFromRawText(raw: string): unknown {
  if (!raw || typeof raw !== 'string') {
    throw new Error('Model output must be a non-empty string');
  }

  let cleaned = raw.trim();

  // Remove markdown fences if present
  const fenceMatch = cleaned.match(/```(?:json)?\s*([\s\S]*?)\s*```/);
  if (fenceMatch) {
    cleaned = fenceMatch[1].trim();
  }

  const firstBrace = cleaned.indexOf('{');
  const lastBrace = cleaned.lastIndexOf('}');

  if (firstBrace === -1 || lastBrace === -1 || lastBrace < firstBrace) {
    throw new Error('No valid JSON object found in model output');
  }

  const jsonStr = cleaned.substring(firstBrace, lastBrace + 1);
  return JSON.parse(jsonStr);
}

/**
 * Extract all used piece names from a flow
 */
function extractPieceNames(flow: Flow): string[] {
  const pieces = new Set<string>();

  function walk(node: any) {
    if (!node || typeof node !== 'object') return;

    if (node.settings?.pieceName) {
      pieces.add(node.settings.pieceName);
    }

    Object.values(node).forEach(walk);
  }

  walk(flow);
  return Array.from(pieces);
}

/**
 * Convert Flow → FlowTemplate
 */
function convertToFlowTemplate(flow: Flow): FlowTemplate {
  return {
    name: flow.displayName || 'Untitled Flow',
    description: 'Flow generated from AI model output',
    tags: [],
    pieces: extractPieceNames(flow),
    template: flow,
    blogUrl: '',
  };
}

/**
 * Main pipeline: raw model output → FlowTemplate JSON
 */
export async function processModelOutputToFlowTemplate(
  rawModelOutput: string
): Promise<string> {
  const parsed = extractJsonFromRawText(rawModelOutput) as unknown;
  const flow = parsed as Flow;

  const template = convertToFlowTemplate(flow);
  return JSON.stringify(template, null, 2);
}

/**
 * Same pipeline, returns object instead of string
 */
export async function processModelOutputToFlowTemplateObject(
  rawModelOutput: string
): Promise<FlowTemplate> {
  const json = await processModelOutputToFlowTemplate(rawModelOutput);
  return JSON.parse(json);
}

/**
 * Lightweight validation (STRUCTURAL ONLY)
 * Required by opsyn.service.ts and index.ts
 */
export function validateFlowTemplate(template: FlowTemplate): {
  isValid: boolean;
  errors: string[];
} {
  const errors: string[] = [];

  if (!template) {
    errors.push('Template is missing');
  }

  if (!template.name) {
    errors.push('Template name is missing');
  }

  if (!template.template) {
    errors.push('Flow template is missing');
  } else {
    if (!template.template.displayName) {
      errors.push('Flow.displayName is missing');
    }
    if (!template.template.trigger) {
      errors.push('Flow.trigger is missing');
    }
  }

  return {
    isValid: errors.length === 0,
    errors,
  };
}

/**
 * Build final prompt sent to the model
 */
export function generateFullPrompt(
  userPrompt: string,
  useExtendedPrompt = false
): string {
  const systemPrompt = useExtendedPrompt
    ? OPSYN_SYSTEM_PROMPT_EXTENDED
    : OPSYN_SYSTEM_PROMPT;

  return `${systemPrompt}\n\nUser Request: ${userPrompt}`;
}
