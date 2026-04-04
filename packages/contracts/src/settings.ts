import { z } from "zod";

export const providerStatusSchema = z.object({
  configured: z.boolean()
});

export const profileSummarySchema = z.object({
  name: z.string(),
  stt_main: z.string(),
  stt_fallback: z.string(),
  llm_main: z.string(),
  llm_fallback: z.string()
});

export const providerSettingsSchema = z.object({
  providers: z.object({
    dashscope_us: providerStatusSchema,
    dashscope_cn: providerStatusSchema,
    openai: providerStatusSchema,
    siliconflow: providerStatusSchema
  }),
  active_profile: z.string(),
  digest_enhancement_enabled: z.boolean(),
  digest_enhancement_provider: z.string(),
  profiles: z.array(profileSummarySchema),
  backend_auth_required: z.boolean()
});

export const providerConnectivityCheckSchema = z.object({
  key: z.string(),
  label: z.string(),
  status: z.enum(["ok", "warn", "fail"]),
  message: z.string()
});

export const providerConnectivitySchema = z.object({
  ready: z.boolean(),
  active_profile: z.string(),
  recommended_stt_provider: z.string(),
  backend_url_reachable: z.boolean(),
  configured_provider_count: z.number().int().nonnegative(),
  checks: z.array(providerConnectivityCheckSchema)
});

export const providerSettingsUpdateSchema = z.object({
  dashscope_key_us: z.string().optional(),
  dashscope_key_cn: z.string().optional(),
  openai_key: z.string().optional(),
  siliconflow_key: z.string().optional(),
  active_profile: z.string().optional(),
  digest_enhancement_enabled: z.boolean().optional(),
  digest_enhancement_provider: z.string().optional()
});

export type ProviderSettings = z.infer<typeof providerSettingsSchema>;
export type ProviderConnectivity = z.infer<typeof providerConnectivitySchema>;
export type ProviderSettingsUpdate = z.infer<typeof providerSettingsUpdateSchema>;
