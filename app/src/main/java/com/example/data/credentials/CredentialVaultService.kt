package com.example.data.credentials

import com.google.firebase.auth.FirebaseAuth
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import org.json.JSONArray
import org.json.JSONObject

/**
 * Android-native client for the shared Cloudflare credential vault.
 * Set AI_AGENT_BASE_URL in Gradle project properties after the Worker is deployed.
 */
class CredentialVaultService(
    private val auth: FirebaseAuth = FirebaseAuth.getInstance(),
    private val client: OkHttpClient = OkHttpClient(),
    private val baseUrl: String = BuildConfig.AI_AGENT_BASE_URL.trimEnd('/')
) {
    private val jsonType = "application/json; charset=utf-8".toMediaType()

    private fun request(method: String, path: String, payload: JSONObject? = null): JSONObject {
        require(baseUrl.startsWith("https://")) { "AI Agent Ultimate no está configurado con HTTPS." }
        val token = auth.currentUser?.getIdToken(false)?.result?.token
            ?: throw IllegalStateException("Inicia sesión para continuar.")
        val builder = Request.Builder()
            .url("$baseUrl$path")
            .header("Authorization", "Bearer $token")
            .header("Accept", "application/json")
        when (method) {
            "GET" -> builder.get()
            "POST" -> builder.post((payload ?: JSONObject()).toString().toRequestBody(jsonType))
            "PATCH" -> builder.patch((payload ?: JSONObject()).toString().toRequestBody(jsonType))
            "DELETE" -> builder.delete()
            else -> error("Método HTTP no permitido.")
        }
        client.newCall(builder.build()).execute().use { response ->
            val text = response.body?.string().orEmpty()
            val result = if (text.isBlank()) JSONObject() else JSONObject(text)
            if (!response.isSuccessful) {
                throw CredentialVaultException(response.code, result.optString("error", "request_failed"))
            }
            return result
        }
    }

    fun list(): JSONArray = request("GET", "/v1/credentials").optJSONArray("credentials") ?: JSONArray()

    fun save(label: String, websiteUrl: String, username: String?, password: String?, draft: Boolean): JSONObject =
        request("POST", "/v1/credentials", JSONObject().apply {
            put("label", label)
            put("website_url", websiteUrl)
            username?.let { put("username", it) }
            password?.let { put("password", it) }
            put("status", if (draft) "draft" else "active")
        })

    fun update(id: String, label: String, websiteUrl: String, username: String?, password: String?, draft: Boolean): JSONObject =
        request("PATCH", "/v1/credentials/$id", JSONObject().apply {
            put("label", label)
            put("website_url", websiteUrl)
            username?.let { put("username", it) }
            password?.let { put("password", it) }
            put("status", if (draft) "draft" else "active")
        })

    fun delete(id: String) {
        request("DELETE", "/v1/credentials/$id")
    }
}

class CredentialVaultException(val statusCode: Int, val code: String) :
    IllegalStateException("Credential vault request failed ($statusCode): $code")
