/**
 * OPSYN Unified Pipeline
 *
 * Complete workflow generation pipeline:
 * 1. JSON extraction and validation
 * 2. Robust post-processing (fixes names, versions, schema)
 * 3. FlowTemplate conversion
 *
 * This is the main entry point for processing AI model output.
 */

import { RobustFlowPostProcessor, Flow } from '../flows/flow-post-processor';

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
 * Extract JSON from raw text
 */
function extractJsonFromRawText(raw: string): unknown {
  if (!raw || typeof raw !== 'string') {
    throw new Error('Input must be a non-empty string');
  }

  let cleaned = raw.trim();

  if (cleaned.includes('```json')) {
    const match = cleaned.match(/```json\s*([\s\S]*?)\s*```/);
    if (match) cleaned = match[1].trim();
  } else if (cleaned.includes('```')) {
    const match = cleaned.match(/```\s*([\s\S]*?)\s*```/);
    if (match) cleaned = match[1].trim();
  }

  const firstBrace = cleaned.indexOf('{');
  if (firstBrace === -1) {
    throw new Error('No JSON object found in input');
  }

  cleaned = cleaned.substring(firstBrace);
  const lastBrace = cleaned.lastIndexOf('}');
  if (lastBrace === -1) {
    throw new Error('Output is truncated (no closing brace found)');
  }

  return JSON.parse(cleaned.substring(0, lastBrace + 1));
}

/**
 * Extract all piece names from a flow
 */
function extractPieceNames(flow: Flow): string[] {
  const pieces = new Set<string>();

  function walk(obj: any) {
    if (!obj || typeof obj !== 'object') return;

    if (obj.settings?.pieceName) {
      pieces.add(obj.settings.pieceName);
    }

    if (obj.trigger) walk(obj.trigger);
    if (obj.nextAction) walk(obj.nextAction);
    if (Array.isArray(obj.children)) obj.children.forEach(walk);
    if (obj.firstLoopAction) walk(obj.firstLoopAction);
  }

  walk(flow);
  return Array.from(pieces);
}

/**
 * Convert processed flow to FlowTemplate format
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
 * Process raw AI model output into FlowTemplate JSON
 */
export async function processModelOutputToFlowTemplate(
  rawModelOutput: string
): Promise<string> {
  const extracted = extractJsonFromRawText(rawModelOutput);

  // Safe cast (TS-required)
  const flow = extracted as unknown as Flow;

  // Robust post-processing (NO args, NO async)
  const processor = new RobustFlowPostProcessor();
  const processedFlow = processor.postProcess(flow);

  const template = convertToFlowTemplate(processedFlow);
  return JSON.stringify(template, null, 2);
}

/**
 * Process model output and return FlowTemplate object
 */
export async function processModelOutputToFlowTemplateObject(
  rawModelOutput: string
): Promise<FlowTemplate> {
  const jsonString = await processModelOutputToFlowTemplate(rawModelOutput);
  return JSON.parse(jsonString);
}

/**
 * Validate a FlowTemplate (lightweight structural check)
 */
export function validateFlowTemplate(
  template: FlowTemplate
): { isValid: boolean; errors: string[] } {
  const errors: string[] = [];

  if (!template.name) errors.push("Missing 'name'");
  if (!template.template) errors.push("Missing 'template'");
  if (!template.template?.trigger) errors.push("Missing 'trigger'");

  return {
    isValid: errors.length === 0,
    errors,
  };
}

/**
 * Generate the full prompt with system prompt
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
