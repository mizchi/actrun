/**
 * Plan a workflow YAML document without executing it.
 *
 * @param yamlText   Workflow YAML source.
 * @param workspaceRoot  Directory used to resolve local paths in the plan.
 * @returns An opaque plan result; pass it to {@link planResultToJson}.
 */
export function planWorkflow(yamlText: string, workspaceRoot: string): unknown;

/** Serialize a plan result produced by {@link planWorkflow} to a JSON string. */
export function planResultToJson(result: unknown): string;
