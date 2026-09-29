// Support console GraphQL client. Own token, separate from the web app's,
// so a support session never mixes with a personal buyer session.
const TOKEN_KEY = 'kyc_admin_token'
const API_URL = (import.meta.env.VITE_API_URL as string | undefined)?.trim() || '/graphql'

export function storedToken() {
  return localStorage.getItem(TOKEN_KEY)
}

export function signOut() {
  localStorage.removeItem(TOKEN_KEY)
}

async function gql<T>(query: string, variables?: Record<string, unknown>): Promise<T> {
  const token = storedToken()
  const res = await fetch(API_URL, {
    method: 'POST',
    headers: {
      'content-type': 'application/json',
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    body: JSON.stringify({ query, variables }),
  })
  const json = (await res.json()) as { data?: T; errors?: { message: string }[] }
  if (json.errors?.length) throw new Error(json.errors[0].message)
  return json.data as T
}

export interface Me {
  id: string
  name: string
  email: string | null
  role: 'USER' | 'ADMIN'
}

export function fetchMe() {
  return gql<{ me: Me | null }>(`query Me { me { id name email role } }`).then((d) => d.me)
}

/** devCode is set only against a dev backend with no email provider. */
export function startEmailSignIn(email: string) {
  return gql<{ startEmailSignIn: { sent: boolean; devCode: string | null } }>(
    `mutation StartEmail($email: String!) { startEmailSignIn(email: $email) { sent devCode } }`,
    { email },
  ).then((d) => d.startEmailSignIn)
}

export async function signInWithEmail(email: string, code: string) {
  const d = await gql<{ signInWithEmail: { token: string; user: Me } }>(
    `mutation EmailSignIn($email: String!, $code: String!) {
      signInWithEmail(email: $email, code: $code) { token user { id name email role } }
    }`,
    { email, code },
  )
  localStorage.setItem(TOKEN_KEY, d.signInWithEmail.token)
  return d.signInWithEmail.user
}

export interface SellerApplication {
  id: string
  status: 'PENDING' | 'APPROVED' | 'REJECTED'
  businessRole: string | null
  contact: string | null
  website: string | null
  note: string | null
  applicant: { name: string; picture: string | null } | null
  createdAt: string
  shop: { id: string; name: string; city: string; address: string }
}

const CLAIM_FIELDS = `id status businessRole contact website note createdAt
  applicant { name picture } shop { id name city address }`

// Oldest first, so support works the queue in order. Requires ADMIN.
export function fetchPendingApplications() {
  return gql<{ pendingClaims: SellerApplication[] }>(
    `query PendingClaims { pendingClaims { ${CLAIM_FIELDS} } }`,
  ).then((d) => d.pendingClaims)
}

// Approval sets the shop's owner, which unlocks the Seller Hub for them.
export function resolveApplication(claimId: string, approve: boolean) {
  return gql<{ resolveClaim: { id: string; status: string } }>(
    `mutation Resolve($claimId: ID!, $approve: Boolean!) {
      resolveClaim(claimId: $claimId, approve: $approve) { id status }
    }`,
    { claimId, approve },
  ).then((d) => d.resolveClaim)
}
