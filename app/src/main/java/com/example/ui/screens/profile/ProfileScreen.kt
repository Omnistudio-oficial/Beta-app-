package com.example.ui.screens.profile

import com.example.data.model.ChannelNotificationPreference

import android.app.TimePickerDialog
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.AccountCircle
import androidx.compose.material.icons.filled.AddPhotoAlternate
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CloudDone
import androidx.compose.material.icons.filled.CloudQueue
import androidx.compose.material.icons.filled.DarkMode
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExitToApp
import androidx.compose.material.icons.filled.LightMode
import androidx.compose.material.icons.filled.LockReset
import androidx.compose.material.icons.filled.PhotoLibrary
import androidx.compose.material.icons.filled.Save
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.Call
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.PhoneMissed
import androidx.compose.material.icons.filled.Timer
import androidx.compose.material.icons.filled.Videocam
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material.icons.filled.Sync
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material.icons.filled.Vibration
import androidx.compose.material.icons.filled.Chat
import androidx.compose.material.icons.filled.Group
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.NotificationsActive
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.filled.Bedtime
import androidx.compose.material.icons.filled.Schedule
import androidx.compose.material.icons.filled.DoNotDisturbOn
import androidx.compose.material.icons.filled.Search
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import coil.compose.AsyncImage
import com.example.ui.viewmodel.OmniViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ProfileScreen(
    viewModel: OmniViewModel,
    onBack: () -> Unit,
    onLogout: () -> Unit,
    onOpenChat: (String) -> Unit = {}
) {
    val authState by viewModel.authUiState.collectAsState()
    val isDarkTheme by viewModel.isDarkTheme.collectAsState()
    val callTimeoutMinutes by viewModel.callTimeoutMinutes.collectAsState()
    val callSoundEnabled by viewModel.callSoundEnabled.collectAsState()
    val callVibrationEnabled by viewModel.callVibrationEnabled.collectAsState()
    val callRingtoneMode by viewModel.callRingtoneMode.collectAsState()
    val availableChannels by viewModel.availableChannels.collectAsState()
    val channelNotificationPrefs by viewModel.channelNotificationPrefs.collectAsState()

    // DND Schedule State
    val dndEnabled by viewModel.dndEnabled.collectAsState()
    val dndStartHour by viewModel.dndStartHour.collectAsState()
    val dndStartMinute by viewModel.dndStartMinute.collectAsState()
    val dndEndHour by viewModel.dndEndHour.collectAsState()
    val dndEndMinute by viewModel.dndEndMinute.collectAsState()
    val dndDays by viewModel.dndDays.collectAsState()

    val context = LocalContext.current
    val isDndActive = remember(dndEnabled, dndStartHour, dndStartMinute, dndEndHour, dndEndMinute, dndDays) {
        viewModel.isDndActiveNow()
    }
    val user = authState.currentUser

    var isEditingProfile by remember { mutableStateOf(false) }
    var editNameInput by remember(user?.displayName) { mutableStateOf(user?.displayName ?: "Alex González") }
    var editAvatarInput by remember(user?.avatarUrl) { mutableStateOf(user?.avatarUrl ?: "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&q=80") }
    var profileSavedFeedback by remember { mutableStateOf(false) }
    var showCredentialVault by remember { mutableStateOf(false) }

    var notificationFilterTab by remember { mutableStateOf(0) }
    var channelSearchQuery by remember { mutableStateOf("") }

    // Launcher del selector de fotos del sistema / galería local de Android
    val profilePhotoPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri: Uri? ->
        if (uri != null) {
            val uriStr = uri.toString()
            editAvatarInput = uriStr
            isEditingProfile = true
            viewModel.updateUserProfile(
                displayName = editNameInput.ifBlank { user?.displayName ?: "Usuario" },
                avatarUrl = uriStr
            )
            profileSavedFeedback = true
        }
    }

    val presetAvatars = listOf(
        "https://images.unsplash.com/photo-1535713875002-d1d0cf377fde?w=200&q=80",
        "https://images.unsplash.com/photo-1570295999919-56ceb5ecca61?w=200&q=80",
        "https://images.unsplash.com/photo-1494790108377-be9c29b29330?w=200&q=80",
        "https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=200&q=80",
        "https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&q=80"
    )

    Scaffold(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding(),
        containerColor = if (isDarkTheme) Color(0xFF0F172A) else Color(0xFFF1F5F9),
        topBar = {
            Surface(
                color = if (isDarkTheme) Color(0xFF1E293B) else Color.White,
                shadowElevation = 2.dp,
                modifier = Modifier.fillMaxWidth()
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 8.dp, vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    IconButton(onClick = onBack, modifier = Modifier.testTag("btn_profile_back")) {
                        Icon(
                            imageVector = Icons.AutoMirrored.Filled.ArrowBack,
                            contentDescription = "Atrás",
                            tint = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                        )
                    }
                    Text(
                        text = "Mi Cuenta Cloud y Ajustes",
                        color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                        fontWeight = FontWeight.Bold,
                        fontSize = 17.sp
                    )
                }
            }
        }
    ) { innerPadding ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(innerPadding)
                .verticalScroll(rememberScrollState())
                .padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            // User Avatar Card with photo preview & clickable camera badge for local photo
            Box(contentAlignment = Alignment.BottomEnd) {
                Surface(
                    modifier = Modifier
                        .size(100.dp)
                        .clip(CircleShape)
                        .clickable {
                            profilePhotoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        }
                        .testTag("btn_avatar_pick_local"),
                    shape = CircleShape,
                    color = Color(0xFF4F46E5),
                    shadowElevation = 4.dp
                ) {
                    val currentPhoto = if (isEditingProfile) editAvatarInput else (user?.avatarUrl ?: "")
                    if (currentPhoto.isNotBlank()) {
                        AsyncImage(
                            model = currentPhoto,
                            contentDescription = "Foto de perfil",
                            modifier = Modifier.fillMaxSize(),
                            contentScale = ContentScale.Crop
                        )
                    } else {
                        Box(contentAlignment = Alignment.Center) {
                            Text(
                                text = (user?.displayName ?: "A").take(1).uppercase(),
                                fontSize = 40.sp,
                                fontWeight = FontWeight.Bold,
                                color = Color.White
                            )
                        }
                    }
                }

                // Badge botón de cámara / galería para cambiar foto local desde el dispositivo
                Surface(
                    shape = CircleShape,
                    color = Color(0xFF4F46E5),
                    border = androidx.compose.foundation.BorderStroke(2.dp, if (isDarkTheme) Color(0xFF0F172A) else Color(0xFFF1F5F9)),
                    modifier = Modifier
                        .size(34.dp)
                        .clickable {
                            profilePhotoPickerLauncher.launch(
                                PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                            )
                        }
                        .testTag("btn_badge_pick_local_photo")
                ) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(
                            imageVector = Icons.Default.AddPhotoAlternate,
                            contentDescription = "Elegir foto del dispositivo",
                            tint = Color.White,
                            modifier = Modifier.size(17.dp)
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = user?.displayName ?: "Alex González",
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
            )

            Text(
                text = user?.email ?: "gonzalez24029@gmail.com",
                fontSize = 13.sp,
                color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
            )

            Spacer(modifier = Modifier.height(8.dp))

            Surface(
                modifier = Modifier.fillMaxWidth().clickable { showCredentialVault = true },
                shape = RoundedCornerShape(12.dp),
                color = if (isDarkTheme) Color(0xFF1E293B) else Color.White
            ) {
                Row(
                    modifier = Modifier.fillMaxWidth().padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(Icons.Default.Security, contentDescription = null)
                    Spacer(modifier = Modifier.width(10.dp))
                    Column(modifier = Modifier.weight(1f)) {
                        Text("Mis credenciales", fontWeight = FontWeight.Bold)
                        Text("Guardar y administrar accesos cifrados", fontSize = 12.sp)
                    }
                    Text("Abrir")
                }
            }

            Surface(
                shape = RoundedCornerShape(12.dp),
                color = if (user?.isGoogleAccount == true) Color(0xFF10B981).copy(alpha = 0.2f) else Color(0xFF6366F1).copy(alpha = 0.2f)
            ) {
                Row(
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    Icon(
                        imageVector = Icons.Default.CloudDone,
                        contentDescription = null,
                        tint = if (user?.isGoogleAccount == true) Color(0xFF34D399) else Color(0xFF818CF8),
                        modifier = Modifier.size(15.dp)
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = if (user?.isGoogleAccount == true) "Autenticado con Google Cloud" else "Cuenta OmniStudio Cloud Activa",
                        fontSize = 12.sp,
                        color = if (user?.isGoogleAccount == true) Color(0xFF34D399) else Color(0xFF818CF8),
                        fontWeight = FontWeight.SemiBold
                    )
                }
            }

            Spacer(modifier = Modifier.height(20.dp))

            // Global Theme Switcher Card (Dark / Light Mode Toggle)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.weight(1f)
                    ) {
                        Surface(
                            shape = CircleShape,
                            color = if (isDarkTheme) Color(0xFF334155) else Color(0xFFFEF3C7),
                            modifier = Modifier.size(42.dp)
                        ) {
                            Box(contentAlignment = Alignment.Center) {
                                Icon(
                                    imageVector = if (isDarkTheme) Icons.Default.DarkMode else Icons.Default.LightMode,
                                    contentDescription = "Tema",
                                    tint = if (isDarkTheme) Color(0xFF818CF8) else Color(0xFFD97706),
                                    modifier = Modifier.size(22.dp)
                                )
                            }
                        }
                        Spacer(modifier = Modifier.width(12.dp))
                        Column {
                            Text(
                                text = if (isDarkTheme) "Modo Oscuro (Dark Theme)" else "Modo Claro (Light Theme)",
                                fontWeight = FontWeight.Bold,
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 14.sp
                            )
                            Text(
                                text = if (isDarkTheme) "Interfaz oscura óptima para descanso visual" else "Interfaz clara de alto contraste",
                                color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                                fontSize = 11.sp
                            )
                        }
                    }

                    Switch(
                        checked = isDarkTheme,
                        onCheckedChange = { viewModel.toggleTheme() },
                        modifier = Modifier.testTag("switch_theme_toggle"),
                        colors = SwitchDefaults.colors(
                            checkedThumbColor = Color.White,
                            checkedTrackColor = Color(0xFF4F46E5),
                            uncheckedThumbColor = Color(0xFFD97706),
                            uncheckedTrackColor = Color(0xFFE2E8F0)
                        )
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Card para Editar Nombre y Foto de Perfil (Cloud Sync)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Default.AccountCircle,
                                contentDescription = null,
                                tint = Color(0xFF818CF8),
                                modifier = Modifier.size(22.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Nombre y Foto de Perfil",
                                fontWeight = FontWeight.Bold,
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 15.sp
                            )
                        }

                        Button(
                            onClick = {
                                isEditingProfile = !isEditingProfile
                                profileSavedFeedback = false
                            },
                            colors = ButtonDefaults.buttonColors(
                                containerColor = if (isEditingProfile) Color(0xFF475569) else Color(0xFF4F46E5)
                            ),
                            shape = RoundedCornerShape(8.dp),
                            modifier = Modifier.testTag("btn_toggle_edit_profile")
                        ) {
                            Icon(
                                imageVector = if (isEditingProfile) Icons.Default.Check else Icons.Default.Edit,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                                tint = Color.White
                            )
                            Spacer(modifier = Modifier.width(4.dp))
                            Text(if (isEditingProfile) "Cerrar" else "Editar", fontSize = 12.sp, color = Color.White)
                        }
                    }

                    if (isEditingProfile) {
                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "Modifica tu nombre público o elige una foto de perfil para que todos los usuarios y grupos la vean en la nube:",
                            color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                            fontSize = 12.sp
                        )

                        Spacer(modifier = Modifier.height(12.dp))

                        OutlinedTextField(
                            value = editNameInput,
                            onValueChange = { editNameInput = it },
                            label = { Text("Nombre visible para todos") },
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("input_edit_display_name"),
                            shape = RoundedCornerShape(10.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                unfocusedTextColor = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                            )
                        )

                        Spacer(modifier = Modifier.height(10.dp))

                        OutlinedTextField(
                            value = editAvatarInput,
                            onValueChange = { editAvatarInput = it },
                            label = { Text("URL de Foto de Perfil") },
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("input_edit_avatar_url"),
                            shape = RoundedCornerShape(10.dp),
                            colors = OutlinedTextFieldDefaults.colors(
                                focusedTextColor = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                unfocusedTextColor = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                            )
                        )

                        Spacer(modifier = Modifier.height(10.dp))

                        // Botón destacado para Elegir Foto del Dispositivo / Galería
                        Button(
                            onClick = {
                                profilePhotoPickerLauncher.launch(
                                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                                )
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(46.dp)
                                .testTag("btn_pick_local_photo_gallery"),
                            colors = ButtonDefaults.buttonColors(
                                containerColor = Color(0xFF4F46E5)
                            ),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Icon(Icons.Default.PhotoLibrary, contentDescription = null, tint = Color.White, modifier = Modifier.size(18.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Elegir Foto del Dispositivo (Galería)",
                                fontWeight = FontWeight.Bold,
                                color = Color.White,
                                fontSize = 13.sp
                            )
                        }

                        Spacer(modifier = Modifier.height(12.dp))
                        Text(
                            text = "O elige un avatar sugerido:",
                            fontSize = 11.sp,
                            color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
                        )
                        Spacer(modifier = Modifier.height(6.dp))

                        LazyRow(
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            items(presetAvatars) { avatarUrl ->
                                val isSelected = editAvatarInput == avatarUrl
                                Surface(
                                    modifier = Modifier
                                        .size(46.dp)
                                        .clip(CircleShape)
                                        .clickable { editAvatarInput = avatarUrl }
                                        .then(
                                            if (isSelected) Modifier.border(2.dp, Color(0xFF4F46E5), CircleShape)
                                            else Modifier
                                        ),
                                    shape = CircleShape
                                ) {
                                    AsyncImage(
                                        model = avatarUrl,
                                        contentDescription = "Avatar preset",
                                        modifier = Modifier.fillMaxSize(),
                                        contentScale = ContentScale.Crop
                                    )
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(14.dp))

                        Button(
                            onClick = {
                                viewModel.updateUserProfile(editNameInput, editAvatarInput)
                                profileSavedFeedback = true
                                isEditingProfile = false
                            },
                            modifier = Modifier
                                .fillMaxWidth()
                                .height(44.dp)
                                .testTag("btn_save_profile_cloud"),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF10B981)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Icon(Icons.Default.Save, contentDescription = null, tint = Color.White)
                            Spacer(modifier = Modifier.width(8.dp))
                            Text("Guardar Cambios en la Nube", fontWeight = FontWeight.Bold, color = Color.White)
                        }
                    }

                    if (profileSavedFeedback) {
                        Spacer(modifier = Modifier.height(8.dp))
                        Surface(
                            shape = RoundedCornerShape(8.dp),
                            color = Color(0xFF10B981).copy(alpha = 0.2f),
                            modifier = Modifier.fillMaxWidth()
                        ) {
                            Row(
                                modifier = Modifier.padding(8.dp),
                                verticalAlignment = Alignment.CenterVertically
                            ) {
                                Icon(Icons.Default.Check, contentDescription = null, tint = Color(0xFF10B981), modifier = Modifier.size(16.dp))
                                Spacer(modifier = Modifier.width(6.dp))
                                Text(
                                    text = "¡Nombre y foto de perfil actualizados y guardados en la nube!",
                                    color = Color(0xFF10B981),
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium
                                )
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Cloud Storage Quota Card
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(Icons.Default.CloudQueue, contentDescription = null, tint = Color(0xFF38BDF8), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = "Almacenamiento en la Nube",
                                fontWeight = FontWeight.Bold,
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 14.sp
                            )
                        }
                        Text(
                            text = "3.4 GB / 15 GB",
                            color = Color(0xFF38BDF8),
                            fontWeight = FontWeight.Bold,
                            fontSize = 12.sp
                        )
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    LinearProgressIndicator(
                        progress = { 0.23f },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(8.dp)
                            .clip(RoundedCornerShape(4.dp)),
                        color = Color(0xFF38BDF8),
                        trackColor = if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0)
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    Text(
                        text = "11.6 GB libres para tus documentos, pistas de audio y mensajes.",
                        color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                        fontSize = 11.sp
                    )
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Security & Realtime Cloud Sync
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Text(
                        text = "Seguridad y Respaldo",
                        fontWeight = FontWeight.Bold,
                        color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                        fontSize = 14.sp,
                        modifier = Modifier.padding(bottom = 8.dp)
                    )

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .clip(RoundedCornerShape(10.dp))
                            .clickable { viewModel.openForgotPassword() }
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.LockReset, contentDescription = null, tint = Color(0xFF818CF8))
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Restablecer Contraseña",
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text("Envía un enlace o código de recuperación a tu correo", color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B), fontSize = 11.sp)
                        }
                    }

                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(Icons.Default.Sync, contentDescription = null, tint = Color(0xFF34D399))
                        Spacer(modifier = Modifier.width(12.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                "Sincronización en Tiempo Real",
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 14.sp,
                                fontWeight = FontWeight.Medium
                            )
                            Text("Activo: Perfil, grupos, docs y chats respaldados", color = Color(0xFF34D399), fontSize = 11.sp)
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // Configuración de Llamadas y Notificaciones (Tiempo de Espera: 1, 3, 4 o 5 minutos)
            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Call, contentDescription = null, tint = Color(0xFF10B981), modifier = Modifier.size(20.dp))
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "Llamadas y Notificaciones",
                            fontWeight = FontWeight.Bold,
                            color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                            fontSize = 15.sp
                        )
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    Text(
                        text = "Tiempo de espera para responder llamadas:",
                        fontWeight = FontWeight.SemiBold,
                        color = if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF334155),
                        fontSize = 13.sp
                    )
                    Text(
                        text = "Si nadie responde dentro de este tiempo, la llamada se congelará automáticamente y se enviará una notificación de llamada perdida.",
                        color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                        fontSize = 11.sp
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    // Selector de 1, 3, 4 y 5 minutos
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        val minuteOptions = listOf(1, 3, 4, 5)
                        minuteOptions.forEach { min ->
                            val isSelected = callTimeoutMinutes == min
                            Surface(
                                shape = RoundedCornerShape(10.dp),
                                color = if (isSelected) Color(0xFF10B981) else if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                                modifier = Modifier
                                    .weight(1f)
                                    .clickable { viewModel.setCallTimeoutMinutes(min) }
                                    .testTag("btn_timeout_${min}min")
                            ) {
                                Column(
                                    modifier = Modifier.padding(vertical = 10.dp),
                                    horizontalAlignment = Alignment.CenterHorizontally
                                ) {
                                    Text(
                                        text = "$min min",
                                        fontWeight = FontWeight.Bold,
                                        fontSize = 13.sp,
                                        color = if (isSelected) Color.White else if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF334155)
                                    )
                                    if (min == 5) {
                                        Text(
                                            text = "Predeterminado",
                                            fontSize = 8.sp,
                                            color = if (isSelected) Color.White.copy(alpha = 0.8f) else Color(0xFF94A3B8)
                                        )
                                    }
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(14.dp))

                    HorizontalDivider(color = if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0))

                    Spacer(modifier = Modifier.height(12.dp))

                    Text(
                        text = "Sonido y Vibración de Llamada:",
                        fontWeight = FontWeight.SemiBold,
                        color = if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF334155),
                        fontSize = 13.sp
                    )

                    Spacer(modifier = Modifier.height(8.dp))

                    // Switch Sonido
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Default.VolumeUp, contentDescription = null, tint = Color(0xFF6366F1), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(10.dp))
                            Column {
                                Text(
                                    "Sonido de timbre",
                                    fontWeight = FontWeight.Medium,
                                    fontSize = 13.sp,
                                    color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                                )
                                Text(
                                    "Reproducir tono y timbre continuo en llamadas",
                                    fontSize = 11.sp,
                                    color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
                                )
                            }
                        }
                        Switch(
                            checked = callSoundEnabled,
                            onCheckedChange = { viewModel.toggleCallSound(it) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = Color(0xFF6366F1)
                            ),
                            modifier = Modifier.testTag("switch_call_sound")
                        )
                    }

                    // Switch Vibración
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(vertical = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.weight(1f)) {
                            Icon(Icons.Default.Vibration, contentDescription = null, tint = Color(0xFF10B981), modifier = Modifier.size(20.dp))
                            Spacer(modifier = Modifier.width(10.dp))
                            Column {
                                Text(
                                    "Vibración continua",
                                    fontWeight = FontWeight.Medium,
                                    fontSize = 13.sp,
                                    color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                                )
                                Text(
                                    "Vibrar en bucle continuo mientras suena la llamada",
                                    fontSize = 11.sp,
                                    color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
                                )
                            }
                        }
                        Switch(
                            checked = callVibrationEnabled,
                            onCheckedChange = { viewModel.toggleCallVibration(it) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = Color(0xFF10B981)
                            ),
                            modifier = Modifier.testTag("switch_call_vibration")
                        )
                    }

                    HorizontalDivider(color = if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0), modifier = Modifier.padding(vertical = 6.dp))

                    // Selector de Tono de Llamada Entrante
                    Column(modifier = Modifier.fillMaxWidth()) {
                        Text(
                            text = "Tono de Llamada Entrante:",
                            fontWeight = FontWeight.Medium,
                            fontSize = 12.sp,
                            color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                        )
                        Spacer(modifier = Modifier.height(6.dp))
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(6.dp)
                        ) {
                            val options = listOf(
                                0 to "🎵 Melódico (Beat)",
                                1 to "🔔 Sistema Android",
                                2 to "⚡ Frecuencia Digital"
                            )
                            options.forEach { (mode, label) ->
                                val isSelected = callRingtoneMode == mode
                                Surface(
                                    onClick = { viewModel.setCallRingtoneMode(mode) },
                                    shape = RoundedCornerShape(8.dp),
                                    color = if (isSelected) Color(0xFF6366F1) else (if (isDarkTheme) Color(0xFF334155) else Color(0xFFF1F5F9)),
                                    modifier = Modifier
                                        .weight(1f)
                                        .testTag("ringtone_option_$mode")
                                ) {
                                    Text(
                                        text = label,
                                        fontSize = 10.sp,
                                        fontWeight = if (isSelected) FontWeight.Bold else FontWeight.Normal,
                                        color = if (isSelected) Color.White else (if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569)),
                                        modifier = Modifier.padding(vertical = 8.dp, horizontal = 4.dp),
                                        textAlign = TextAlign.Center
                                    )
                                }
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(8.dp)
                    ) {
                        // Botón probar sonido y vibración rápido (3s)
                        Button(
                            onClick = { viewModel.testCallSoundAndVibration() },
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp)
                                .testTag("btn_test_sound_vib"),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF6366F1)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                            Icon(Icons.Default.VolumeUp, contentDescription = null, tint = Color.White, modifier = Modifier.size(15.dp))
                            Spacer(modifier = Modifier.width(4.dp))
                            Text("Probar Audio/Vib", fontWeight = FontWeight.SemiBold, fontSize = 11.sp, color = Color.White)
                        }

                        // Botón para probar la notificación de llamada entrante en vivo
                        Button(
                            onClick = {
                                viewModel.simulateIncomingCall(
                                    peerName = "Sofia Martínez",
                                    peerEmail = "sofia.m@cloud.io",
                                    isVideo = true,
                                    groupName = "Equipo Diseño UI/UX"
                                )
                            },
                            modifier = Modifier
                                .weight(1f)
                                .height(42.dp)
                                .testTag("btn_test_incoming_call"),
                            colors = ButtonDefaults.buttonColors(containerColor = Color(0xFF10B981)),
                            shape = RoundedCornerShape(10.dp)
                        ) {
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // CARD: Programación Horario No Molestar (DND)
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .testTag("card_dnd_schedule"),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Surface(
                                shape = RoundedCornerShape(10.dp),
                                color = Color(0xFF8B5CF6).copy(alpha = 0.15f),
                                modifier = Modifier.size(38.dp)
                            ) {
                                Box(contentAlignment = Alignment.Center) {
                                    Icon(
                                        imageVector = Icons.Default.Bedtime,
                                        contentDescription = null,
                                        tint = Color(0xFF8B5CF6),
                                        modifier = Modifier.size(20.dp)
                                    )
                                }
                            }
                            Spacer(modifier = Modifier.width(12.dp))
                            Column {
                                Text(
                                    text = "Horario No Molestar (DND)",
                                    fontWeight = FontWeight.Bold,
                                    fontSize = 15.sp,
                                    color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                                )
                                Text(
                                    text = "Silencia alertas y llamadas automáticamente",
                                    fontSize = 11.sp,
                                    color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
                                )
                            }
                        }

                        Switch(
                            checked = dndEnabled,
                            onCheckedChange = { viewModel.setDndEnabled(it) },
                            colors = SwitchDefaults.colors(
                                checkedThumbColor = Color.White,
                                checkedTrackColor = Color(0xFF8B5CF6)
                            ),
                            modifier = Modifier.testTag("switch_dnd_enabled")
                        )
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    // Chip de estado DND actual
                    Surface(
                        shape = RoundedCornerShape(10.dp),
                        color = if (dndEnabled && isDndActive) Color(0xFF8B5CF6) else (if (isDarkTheme) Color(0xFF334155) else Color(0xFFF1F5F9)),
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Row(
                            modifier = Modifier.padding(vertical = 8.dp, horizontal = 12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Icon(
                                imageVector = if (dndEnabled && isDndActive) Icons.Default.DoNotDisturbOn else Icons.Default.Schedule,
                                contentDescription = null,
                                tint = if (dndEnabled && isDndActive) Color.White else (if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)),
                                modifier = Modifier.size(16.dp)
                            )
                            Spacer(modifier = Modifier.width(8.dp))
                            Text(
                                text = when {
                                    dndEnabled && isDndActive -> "🌙 MODO NO MOLESTAR ACTIVO (Sonido y vibración silenciados)"
                                    dndEnabled -> String.format("⏰ Programado activo: %02d:%02d a %02d:%02d", dndStartHour, dndStartMinute, dndEndHour, dndEndMinute)
                                    else -> "💤 Horario No Molestar desactivado"
                                },
                                fontSize = 11.sp,
                                fontWeight = FontWeight.SemiBold,
                                color = if (dndEnabled && isDndActive) Color.White else (if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569))
                            )
                        }
                    }

                    if (dndEnabled) {
                        Spacer(modifier = Modifier.height(14.dp))
                        HorizontalDivider(color = if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0))
                        Spacer(modifier = Modifier.height(12.dp))

                        // Horas de Inicio y Fin
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.spacedBy(10.dp)
                        ) {
                            // Selector Hora Inicio
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Hora de Inicio:",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569)
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Surface(
                                    onClick = {
                                        TimePickerDialog(
                                            context,
                                            { _, hour, minute -> viewModel.setDndStartTime(hour, minute) },
                                            dndStartHour,
                                            dndStartMinute,
                                            true
                                        ).show()
                                    },
                                    shape = RoundedCornerShape(10.dp),
                                    color = if (isDarkTheme) Color(0xFF0F172A) else Color(0xFFF8FAFC),
                                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF8B5CF6).copy(alpha = 0.5f)),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("btn_dnd_start_time")
                                ) {
                                    Row(
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(
                                            text = String.format("%02d:%02d", dndStartHour, dndStartMinute),
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 14.sp,
                                            color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                                        )
                                        Icon(
                                            Icons.Default.Schedule,
                                            contentDescription = null,
                                            tint = Color(0xFF8B5CF6),
                                            modifier = Modifier.size(16.dp)
                                        )
                                    }
                                }
                            }

                            // Selector Hora Fin
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    text = "Hora de Fin:",
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.Medium,
                                    color = if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569)
                                )
                                Spacer(modifier = Modifier.height(4.dp))
                                Surface(
                                    onClick = {
                                        TimePickerDialog(
                                            context,
                                            { _, hour, minute -> viewModel.setDndEndTime(hour, minute) },
                                            dndEndHour,
                                            dndEndMinute,
                                            true
                                        ).show()
                                    },
                                    shape = RoundedCornerShape(10.dp),
                                    color = if (isDarkTheme) Color(0xFF0F172A) else Color(0xFFF8FAFC),
                                    border = androidx.compose.foundation.BorderStroke(1.dp, Color(0xFF8B5CF6).copy(alpha = 0.5f)),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .testTag("btn_dnd_end_time")
                                ) {
                                    Row(
                                        modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp),
                                        verticalAlignment = Alignment.CenterVertically,
                                        horizontalArrangement = Arrangement.SpaceBetween
                                    ) {
                                        Text(
                                            text = String.format("%02d:%02d", dndEndHour, dndEndMinute),
                                            fontWeight = FontWeight.Bold,
                                            fontSize = 14.sp,
                                            color = if (isDarkTheme) Color.White else Color(0xFF0F172A)
                                        )
                                        Icon(
                                            Icons.Default.Schedule,
                                            contentDescription = null,
                                            tint = Color(0xFF8B5CF6),
                                            modifier = Modifier.size(16.dp)
                                        )
                                    }
                                }
                            }
                        }

                        Spacer(modifier = Modifier.height(14.dp))

                        // Días de la semana
                        Text(
                            text = "Días activos:",
                            fontSize = 11.sp,
                            fontWeight = FontWeight.Medium,
                            color = if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569)
                        )
                        Spacer(modifier = Modifier.height(6.dp))

                        val daysList = listOf(
                            1 to "L",
                            2 to "M",
                            3 to "X",
                            4 to "J",
                            5 to "V",
                            6 to "S",
                            7 to "D"
                        )
                        Row(
                            modifier = Modifier.fillMaxWidth(),
                            horizontalArrangement = Arrangement.SpaceBetween
                        ) {
                            daysList.forEach { (dayIdx, label) ->
                                val isSelected = dndDays.contains(dayIdx)
                                Surface(
                                    onClick = { viewModel.toggleDndDay(dayIdx) },
                                    shape = CircleShape,
                                    color = if (isSelected) Color(0xFF8B5CF6) else (if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0)),
                                    modifier = Modifier
                                        .size(36.dp)
                                        .testTag("dnd_day_chip_$dayIdx")
                                ) {
                                    Box(contentAlignment = Alignment.Center) {
                                        Text(
                                            text = label,
                                            fontSize = 12.sp,
                                            fontWeight = FontWeight.Bold,
                                            color = if (isSelected) Color.White else (if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF475569))
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(16.dp))

            // CARD: Preferencias de Notificaciones por Grupo y Chat Privado
            Card(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp)
                    .testTag("card_channel_notification_settings"),
                colors = CardDefaults.cardColors(
                    containerColor = if (isDarkTheme) Color(0xFF1E293B) else Color.White
                ),
                shape = RoundedCornerShape(16.dp),
                elevation = CardDefaults.cardElevation(defaultElevation = 2.dp)
            ) {
                Column(modifier = Modifier.padding(16.dp)) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(
                            imageVector = Icons.Default.NotificationsActive,
                            contentDescription = null,
                            tint = Color(0xFF8B5CF6),
                            modifier = Modifier.size(22.dp)
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Column(modifier = Modifier.weight(1f)) {
                            Text(
                                text = "Notificaciones por Chat y Grupo",
                                fontWeight = FontWeight.Bold,
                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                fontSize = 15.sp
                            )
                            Text(
                                text = "Activa o desactiva alertas de mensajes, voz y video para cada chat",
                                color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B),
                                fontSize = 11.sp
                            )
                        }
                    }

                    Spacer(modifier = Modifier.height(12.dp))

                    // Selector de filtro: Todos / Grupos / Chats Privados
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.spacedBy(6.dp)
                    ) {
                        listOf("Todos (${availableChannels.size})", "Grupos", "Privados").forEachIndexed { idx, label ->
                            val isSel = notificationFilterTab == idx
                            Surface(
                                shape = RoundedCornerShape(8.dp),
                                color = if (isSel) Color(0xFF8B5CF6) else if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                                modifier = Modifier
                                    .weight(1f)
                                    .clickable { notificationFilterTab = idx }
                            ) {
                                Text(
                                    text = label,
                                    fontSize = 11.sp,
                                    fontWeight = FontWeight.SemiBold,
                                    color = if (isSel) Color.White else if (isDarkTheme) Color(0xFFCBD5E1) else Color(0xFF334155),
                                    textAlign = TextAlign.Center,
                                    modifier = Modifier.padding(vertical = 6.dp)
                                )
                            }
                        }
                    }

                    Spacer(modifier = Modifier.height(10.dp))

                    // Buscador rápido
                    OutlinedTextField(
                        value = channelSearchQuery,
                        onValueChange = { channelSearchQuery = it },
                        placeholder = { Text("Buscar chat o grupo...", fontSize = 12.sp) },
                        leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = Color.Gray, modifier = Modifier.size(16.dp)) },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(48.dp),
                        shape = RoundedCornerShape(10.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedBorderColor = Color(0xFF8B5CF6),
                            unfocusedBorderColor = if (isDarkTheme) Color(0xFF475569) else Color(0xFFCBD5E1)
                        ),
                        singleLine = true
                    )

                    Spacer(modifier = Modifier.height(12.dp))

                    val filteredChannels = availableChannels.filter { chan ->
                        val matchesFilter = when (notificationFilterTab) {
                            1 -> chan.isGroup
                            2 -> !chan.isGroup
                            else -> true
                        }
                        val matchesSearch = channelSearchQuery.isBlank() || chan.name.contains(channelSearchQuery, ignoreCase = true)
                        matchesFilter && matchesSearch
                    }

                    if (filteredChannels.isEmpty()) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = 16.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text(
                                text = "No se encontraron chats o grupos",
                                fontSize = 12.sp,
                                color = if (isDarkTheme) Color(0xFF94A3B8) else Color(0xFF64748B)
                            )
                        }
                    } else {
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            filteredChannels.forEach { channel ->
                                val pref = channelNotificationPrefs[channel.id] ?: ChannelNotificationPreference(channel.id)

                                Surface(
                                    shape = RoundedCornerShape(12.dp),
                                    color = if (isDarkTheme) Color(0xFF0F172A) else Color(0xFFF8FAFC),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onOpenChat(channel.id) }
                                ) {
                                    Column(modifier = Modifier.padding(10.dp)) {
                                        // Cabecera del chat
                                        Row(
                                            verticalAlignment = Alignment.CenterVertically,
                                            modifier = Modifier.fillMaxWidth()
                                        ) {
                                            Text(
                                                text = channel.iconEmoji.ifBlank { if (channel.isGroup) "👥" else "💬" },
                                                fontSize = 15.sp
                                            )
                                            Spacer(modifier = Modifier.width(8.dp))
                                            Text(
                                                text = channel.name,
                                                fontWeight = FontWeight.Bold,
                                                fontSize = 12.sp,
                                                color = if (isDarkTheme) Color.White else Color(0xFF0F172A),
                                                modifier = Modifier.weight(1f)
                                            )
                                            Surface(
                                                shape = RoundedCornerShape(6.dp),
                                                color = if (channel.isGroup) Color(0xFF7C3AED).copy(alpha = 0.2f) else Color(0xFF0284C7).copy(alpha = 0.2f)
                                            ) {
                                                Text(
                                                    text = if (channel.isGroup) "Grupo" else "Privado",
                                                    fontSize = 9.sp,
                                                    fontWeight = FontWeight.Bold,
                                                    color = if (channel.isGroup) Color(0xFFC4B5FD) else Color(0xFF38BDF8),
                                                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                                                )
                                            }
                                        }

                                        Spacer(modifier = Modifier.height(8.dp))

                                        // Controles para Mensajes, Llamadas de Voz, Videollamadas
                                        Row(
                                            modifier = Modifier.fillMaxWidth(),
                                            horizontalArrangement = Arrangement.SpaceBetween,
                                            verticalAlignment = Alignment.CenterVertically
                                        ) {
                                            // Chip / Toggle Mensajes
                                            Surface(
                                                shape = RoundedCornerShape(8.dp),
                                                color = if (pref.notifyMessages) Color(0xFF10B981).copy(alpha = 0.15f) else if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                                                modifier = Modifier
                                                    .weight(1f)
                                                    .clickable { viewModel.toggleChannelNotifyMessages(channel.id) }
                                                    .testTag("chip_notify_msg_${channel.id}")
                                            ) {
                                                Row(
                                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.Center
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Default.Chat,
                                                        contentDescription = null,
                                                        tint = if (pref.notifyMessages) Color(0xFF10B981) else Color.Gray,
                                                        modifier = Modifier.size(12.dp)
                                                    )
                                                    Spacer(modifier = Modifier.width(3.dp))
                                                    Text(
                                                        text = if (pref.notifyMessages) "Msgs: On" else "Msgs: Off",
                                                        fontSize = 10.sp,
                                                        fontWeight = FontWeight.Bold,
                                                        color = if (pref.notifyMessages) Color(0xFF10B981) else Color.Gray
                                                    )
                                                }
                                            }

                                            Spacer(modifier = Modifier.width(4.dp))

                                            // Chip / Toggle Llamadas Voz
                                            Surface(
                                                shape = RoundedCornerShape(8.dp),
                                                color = if (pref.notifyVoiceCalls) Color(0xFF3B82F6).copy(alpha = 0.15f) else if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                                                modifier = Modifier
                                                    .weight(1f)
                                                    .clickable { viewModel.toggleChannelNotifyVoiceCalls(channel.id) }
                                                    .testTag("chip_notify_voice_${channel.id}")
                                            ) {
                                                Row(
                                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.Center
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Default.Call,
                                                        contentDescription = null,
                                                        tint = if (pref.notifyVoiceCalls) Color(0xFF3B82F6) else Color.Gray,
                                                        modifier = Modifier.size(12.dp)
                                                    )
                                                    Spacer(modifier = Modifier.width(3.dp))
                                                    Text(
                                                        text = if (pref.notifyVoiceCalls) "Voz: On" else "Voz: Off",
                                                        fontSize = 10.sp,
                                                        fontWeight = FontWeight.Bold,
                                                        color = if (pref.notifyVoiceCalls) Color(0xFF3B82F6) else Color.Gray
                                                    )
                                                }
                                            }

                                            Spacer(modifier = Modifier.width(4.dp))

                                            // Chip / Toggle Videollamadas
                                            Surface(
                                                shape = RoundedCornerShape(8.dp),
                                                color = if (pref.notifyVideoCalls) Color(0xFF8B5CF6).copy(alpha = 0.15f) else if (isDarkTheme) Color(0xFF334155) else Color(0xFFE2E8F0),
                                                modifier = Modifier
                                                    .weight(1f)
                                                    .clickable { viewModel.toggleChannelNotifyVideoCalls(channel.id) }
                                                    .testTag("chip_notify_video_${channel.id}")
                                            ) {
                                                Row(
                                                    modifier = Modifier.padding(horizontal = 4.dp, vertical = 6.dp),
                                                    verticalAlignment = Alignment.CenterVertically,
                                                    horizontalArrangement = Arrangement.Center
                                                ) {
                                                    Icon(
                                                        imageVector = Icons.Default.Videocam,
                                                        contentDescription = null,
                                                        tint = if (pref.notifyVideoCalls) Color(0xFF8B5CF6) else Color.Gray,
                                                        modifier = Modifier.size(12.dp)
                                                    )
                                                    Spacer(modifier = Modifier.width(3.dp))
                                                    Text(
                                                        text = if (pref.notifyVideoCalls) "Video: On" else "Video: Off",
                                                        fontSize = 10.sp,
                                                        fontWeight = FontWeight.Bold,
                                                        color = if (pref.notifyVideoCalls) Color(0xFF8B5CF6) else Color.Gray
                                                    )
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.height(24.dp))

            // Logout Button
            Button(
                onClick = {
                    try {
                        com.google.firebase.auth.FirebaseAuth.getInstance().signOut()
                    } catch (_: Exception) {}
                    viewModel.logout()
                    onLogout()
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp)
                    .testTag("btn_logout"),
                colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFEF4444)),
                shape = RoundedCornerShape(12.dp)
            ) {
                Icon(Icons.Default.ExitToApp, contentDescription = null, tint = Color.White)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Cerrar Sesión", fontWeight = FontWeight.Bold, color = Color.White)
            }
        }
    }
    if (showCredentialVault) {
        CredentialVaultDialog(onDismiss = { showCredentialVault = false })
    }
}
