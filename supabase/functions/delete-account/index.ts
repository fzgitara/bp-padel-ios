import { createClient } from "npm:@supabase/supabase-js@2";

// Deletes the calling user. Cascades remove their profile, tournaments, players and memberships.
Deno.serve(async (req) => {
  const authorization = req.headers.get("Authorization");
  if (!authorization) return new Response("unauthorized", { status: 401 });

  const url = Deno.env.get("SUPABASE_URL")!;
  const userClient = createClient(url, Deno.env.get("SUPABASE_ANON_KEY")!, {
    global: { headers: { Authorization: authorization } },
  });
  const { data, error } = await userClient.auth.getUser();
  if (error || !data.user) return new Response("unauthorized", { status: 401 });

  const admin = createClient(url, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const { error: deleteError } = await admin.auth.admin.deleteUser(data.user.id);
  if (deleteError) return new Response(deleteError.message, { status: 500 });

  return new Response(null, { status: 204 });
});
