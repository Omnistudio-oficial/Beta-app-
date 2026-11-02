package com.example.ui.screens.profile

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Checkbox
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.unit.dp
import com.example.data.credentials.CredentialVaultService
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun CredentialVaultDialog(onDismiss: () -> Unit) {
    val service = remember { CredentialVaultService() }
    val scope = rememberCoroutineScope()
    val credentials = remember { mutableStateListOf<JSONObject>() }
    var label by remember { mutableStateOf("") }
    var website by remember { mutableStateOf("") }
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var editingId by remember { mutableStateOf<String?>(null) }
    var draft by remember { mutableStateOf(false) }
    var busy by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }

    fun refresh() {
        scope.launch {
            busy = true
            try {
                val rows = service.list()
                credentials.clear()
                for (i in 0 until rows.length()) rows.optJSONObject(i)?.let(credentials::add)
                error = null
            } catch (e: Exception) {
                error = e.message ?: "No se pudieron cargar las credenciales."
            } finally { busy = false }
        }
    }
    LaunchedEffect(Unit) { refresh() }

    Dialog(onDismissRequest = onDismiss) {
        Column(
            modifier = Modifier.fillMaxWidth().heightIn(max = 620.dp)
                .verticalScroll(rememberScrollState()).padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp)
        ) {
            Text("Mis credenciales")
            Text("Los datos se cifran en el servidor. La lista solo muestra metadatos.")
            OutlinedTextField(label, { label = it }, label = { Text("Nombre") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(website, { website = it }, label = { Text("Sitio web HTTPS") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(username, { username = it }, label = { Text("Usuario (vuelve a escribirlo al editar)") }, modifier = Modifier.fillMaxWidth())
            OutlinedTextField(password, { password = it }, label = { Text("Contraseña (vuelve a escribirla al editar)") }, modifier = Modifier.fillMaxWidth())
            Row {
                Checkbox(checked = draft, onCheckedChange = { draft = it })
                Text("Guardar como borrador")
            }
            Button(
                enabled = !busy && label.isNotBlank() && website.isNotBlank(),
                onClick = {
                    scope.launch {
                        busy = true
                        try {
                            val id = editingId
                            if (id == null) service.save(label, website, username.takeIf(String::isNotEmpty), password.takeIf(String::isNotEmpty), draft)
                            else service.update(id, label, website, username.takeIf(String::isNotEmpty), password.takeIf(String::isNotEmpty), draft)
                            label = ""; website = ""; username = ""; password = ""; editingId = null; draft = false
                            refresh()
                        } catch (e: Exception) { error = e.message ?: "No se pudo guardar." }
                        finally { busy = false }
                    }
                },
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (editingId == null) "Guardar" else "Actualizar") }
            if (editingId != null) TextButton(onClick = { editingId = null; label = ""; website = ""; username = ""; password = ""; draft = false }) { Text("Cancelar edición") }
            error?.let { Text(it) }
            Text("Guardadas")
            credentials.forEach { item ->
                val id = item.optString("id")
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Column(modifier = Modifier.weight(1f)) {
                        Text(item.optString("label"))
                        Text(item.optString("origin") + " · " + item.optString("status"))
                    }
                    TextButton(onClick = {
                        editingId = id
                        label = item.optString("label")
                        website = item.optString("origin")
                        username = ""; password = ""
                        draft = item.optString("status") == "draft"
                    }) { Text("Editar") }
                    TextButton(onClick = {
                        scope.launch {
                            busy = true
                            try { service.delete(id); refresh() }
                            catch (e: Exception) { error = e.message ?: "No se pudo eliminar." }
                            finally { busy = false }
                        }
                    }) { Text("Eliminar") }
                }
            }
            TextButton(onClick = onDismiss, modifier = Modifier.fillMaxWidth()) { Text("Cerrar") }
        }
    }
}
