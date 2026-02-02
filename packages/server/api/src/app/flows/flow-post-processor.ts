/**
 * Robust Flow Post-Processor for Activepieces
 * 
 * Converts raw AI model output into valid Activepieces flow JSON.
 * Fixes common schema issues and ensures compatibility.
 */

/**
 * Base Flow type matching Activepieces schema
 */
export interface Flow {
  displayName: string;
  schemaVersion?: string;
  trigger: FlowTrigger;
}

/**
 * Flow Trigger - can be empty or piece-based
 */
export type FlowTrigger = EmptyTrigger | PieceTrigger;

export interface EmptyTrigger {
  type: 'EMPTY';
  name: string;
  valid: boolean;
  displayName: string;
  settings: Record<string, unknown>;
  nextAction?: FlowAction;
}

export interface PieceTrigger {
  type: 'PIECE_TRIGGER';
  name: string;
  valid: boolean;
  displayName: string;
  settings: PieceTriggerSettings;
  nextAction?: FlowAction;
}

export interface PieceTriggerSettings {
  pieceName: string;
  pieceVersion: string;
  triggerName?: string;
  input: Record<string, unknown>;
  propertySettings: Record<string, PropertySettings>;
  sampleData?: unknown;
  customLogoUrl?: string;
}

export interface PropertySettings {
  required?: boolean;
  [key: string]: unknown;
}

/**
 * Flow Action in the pipeline
 */
export interface FlowAction {
  type: 'PIECE_ACTION' | 'ROUTER' | 'BRANCH_ACTION';
  name: string;
  valid: boolean;
  displayName: string;
  settings?: Record<string, unknown>;
  nextAction?: FlowAction;
  onFailureAction?: FlowAction;
  onSuccessAction?: FlowAction;
  [key: string]: unknown;
}

/**
 * Robust Flow Post-Processor
 * 
 * Fixes common issues from AI model output:
 * - Wrong trigger/action names
 * - Missing schema version
 * - Incorrect field names
 * - Missing propertySettings
 */
export class RobustFlowPostProcessor {
  private targetSchemaVersion = '10';

  /**
   * Process a flow and fix all issues
   */
  processFlow(flow: unknown): Flow {
    if (typeof flow !== 'object' || flow === null) {
      throw new Error('Flow must be an object');
    }

    const flowObj = JSON.parse(JSON.stringify(flow)) as Record<string, unknown>;

    // Fix root level issues
    this.fixRootLevel(flowObj);

    // Fix trigger
    if (flowObj.trigger) {
      flowObj.trigger = this.fixTrigger(flowObj.trigger as Record<string, unknown>);
    }

    // Fix actions recursively
    if (flowObj.trigger && typeof flowObj.trigger === 'object' && flowObj.trigger !== null) {
      const trigger = flowObj.trigger as Record<string, unknown>;
      if (trigger.nextAction) {
        trigger.nextAction = this.fixAction(trigger.nextAction as Record<string, unknown>);
      }
    }

    return flowObj as unknown as Flow;

  }

  /**
   * Fix root level issues
   */
  private fixRootLevel(flow: Record<string, unknown>): void {
    // Fix name -> displayName
    if ('name' in flow && !('displayName' in flow)) {
      flow.displayName = flow.name;
      delete flow.name;
    }

    // Fix schemaVersion
    if (!flow.schemaVersion || flow.schemaVersion === 'null' || flow.schemaVersion === null) {
      flow.schemaVersion = this.targetSchemaVersion;
    }
  }

  /**
   * Fix trigger
   */
  private fixTrigger(trigger: Record<string, unknown>): Record<string, unknown> {
    // Fix displayName
    if ('name' in trigger && !('displayName' in trigger)) {
      trigger.displayName = trigger.name as string;
    }

    // Fix type
    if (!trigger.type) {
      trigger.type = 'EMPTY';
    }

    // Fix valid
    if (!('valid' in trigger)) {
      trigger.valid = true;
    }

    // Fix settings
    if (trigger.type === 'PIECE_TRIGGER' && typeof trigger.settings === 'object') {
      trigger.settings = this.fixPieceTriggerSettings(trigger.settings as Record<string, unknown>);
    }

    return trigger;
  }

  /**
   * Fix piece trigger settings
   */
  private fixPieceTriggerSettings(settings: Record<string, unknown>): Record<string, unknown> {
    // Ensure propertySettings exists
    if (!settings.propertySettings || typeof settings.propertySettings !== 'object') {
      settings.propertySettings = {};
    }

    // Ensure input exists
    if (!settings.input || typeof settings.input !== 'object') {
      settings.input = {};
    }

    return settings;
  }

  /**
   * Fix action recursively
   */
  private fixAction(action: Record<string, unknown>): Record<string, unknown> {
    if (!action) {
      return action;
    }

    const fixed = JSON.parse(JSON.stringify(action)) as Record<string, unknown>;

    // Fix displayName
    if ('name' in fixed && !('displayName' in fixed)) {
      fixed.displayName = fixed.name as string;
    }

    // Fix type - convert CONDITION to ROUTER
    if (fixed.type === 'CONDITION') {
      fixed.type = 'ROUTER';
    }

    // Fix valid
    if (!('valid' in fixed)) {
      fixed.valid = true;
    }

    // Fix settings for piece actions
    if (fixed.type === 'PIECE_ACTION' && typeof fixed.settings === 'object') {
      fixed.settings = this.fixPieceTriggerSettings(fixed.settings as Record<string, unknown>);
    }

    // Fix nextAction recursively
    if (fixed.nextAction && typeof fixed.nextAction === 'object') {
      fixed.nextAction = this.fixAction(fixed.nextAction as Record<string, unknown>);
    }

    // Fix onSuccessAction for ROUTER
    if (fixed.type === 'ROUTER' && fixed.onSuccessAction && typeof fixed.onSuccessAction === 'object') {
      fixed.onSuccessAction = this.fixAction(fixed.onSuccessAction as Record<string, unknown>);
    }

    // Fix onFailureAction
    if (fixed.onFailureAction && typeof fixed.onFailureAction === 'object') {
      fixed.onFailureAction = this.fixAction(fixed.onFailureAction as Record<string, unknown>);
    }

    return fixed;
  }

  /**
   * Validate flow schema
   */
  validateFlow(flow: Flow): { valid: boolean; errors: string[] } {
    const errors: string[] = [];

    // Check required fields
    if (!flow.displayName) {
      errors.push('Missing displayName');
    }
    if (!flow.trigger) {
      errors.push('Missing trigger');
    }
    if (flow.trigger && !flow.trigger.type) {
      errors.push('Trigger missing type');
    }

    return {
      valid: errors.length === 0,
      errors,
    };
  }
}

/**
 * Helper to create a simple empty trigger flow
 */
export function createEmptyFlow(displayName: string): Flow {
  return {
    displayName,
    schemaVersion: '10',
    trigger: {
      type: 'EMPTY',
      name: 'trigger',
      valid: true,
      displayName: 'Start',
      settings: {},
    },
  };
}
