package com.example.ui.screens.social

import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Bookmark
import androidx.compose.material.icons.filled.BookmarkBorder
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Comment
import androidx.compose.material.icons.filled.Favorite
import androidx.compose.material.icons.filled.FavoriteBorder
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.produceState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.viewinterop.AndroidView
import coil.compose.AsyncImage
import com.example.ui.components.StandardVideoPlayerDialog
import com.example.ui.components.VideoPlayer
import com.example.data.social.SocialComment
import com.example.data.social.SocialFollowRequest
import com.example.data.social.SocialPost
import com.example.data.social.SocialPostMedia
import com.example.data.social.SocialMediaUpload
import com.example.data.social.SocialMediaUploadLimits
import com.example.data.social.SocialPostPublishPolicy
import com.example.data.social.SocialVideoAutoSplitter
import com.example.data.social.SocialProfile
import com.example.data.social.SocialStory
import android.net.Uri
import android.util.Log
import com.example.BuildConfig
import com.example.data.social.SocialRepository
import com.example.ui.viewmodel.OmniViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import android.content.Context
import android.media.MediaPlayer
import android.view.Gravity
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.VideoView

private const val SOCIAL_DIAGNOSTIC_TAG = "SocialFeedDiag"

/** Debug-only, non-identifying feed diagnostics. Never pass post/profile/media identifiers or URLs. */
private fun socialDiagnostic(event: String, index: Int? = null, mediaType: String? = null, code: Int? = null, count: Int? = null, error: Throwable? = null, errorClass: String? = null) {
    if (!BuildConfig.DEBUG) return
    val details = buildList {
        add("event=$event")
        index?.let { add("index=$it") }
        mediaType?.let { add("mediaType=$it") }
        code?.let { add("code=$it") }
        count?.let { add("count=$it") }
        error?.let { add("exception=${it.javaClass.simpleName}") }
        errorClass?.let { add("exception=$it") }
    }.joinToString(" ")
    Log.d(SOCIAL_DIAGNOSTIC_TAG, details)
}

private enum class SocialSection(val label: String) {
    FOR_YOU("Para ti"), FOLLOWING("Siguiendo"), VIDEOS("Videos"), SAVED("Ver más tarde"), SEARCH("Buscar"), PROFILE("Perfil")
}

@Composable
fun SocialScreen(
    viewModel: OmniViewModel,
    onBack: () -> Unit
) {
    val authState by viewModel.authUiState.collectAsState()
    val currentUser = authState.currentUser
    val context = LocalContext.current
    val repository = remember(context) { SocialRepository(context) }
    val scope = rememberCoroutineScope()

    DisposableEffect(Unit) {
        socialDiagnostic("screen_enter")
        onDispose { socialDiagnostic("screen_exit") }
    }

    var myProfile by remember { mutableStateOf<SocialProfile?>(null) }
    var viewingProfile by remember { mutableStateOf<SocialProfile?>(null) }
    var profilePosts by remember { mutableStateOf<List<SocialPost>>(emptyList()) }
    var feed by remember { mutableStateOf<List<SocialPost>>(emptyList()) }
    var stories by remember { mutableStateOf<List<SocialStory>>(emptyList()) }
    var searchResults by remember { mutableStateOf<List<SocialProfile>>(emptyList()) }
    var followRequests by remember { mutableStateOf<List<SocialFollowRequest>>(emptyList()) }
    var followedState by remember { mutableStateOf<Map<String, String>>(emptyMap()) }
    var selectedSection by remember { mutableStateOf(SocialSection.FOR_YOU) }
    var searchQuery by remember { mutableStateOf("") }
    var newPostText by remember { mutableStateOf("") }
    var selectedPostOriginalUris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    var newPostMediaUris by remember { mutableStateOf<List<Uri>>(emptyList()) }
    var isPreparingPostMedia by remember { mutableStateOf(false) }
    var isPublishingPost by remember { mutableStateOf(false) }
    var postMediaPreflightError by remember { mutableStateOf<String?>(null) }
    var postUploadError by remember { mutableStateOf<String?>(null) }
    var postSplitSummary by remember { mutableStateOf<String?>(null) }
    val generatedPostClipFiles = remember { androidx.compose.runtime.mutableStateListOf<File>() }
    var postMediaPreparationGeneration by remember { mutableIntStateOf(0) }
    var postMediaPreparationJob by remember { mutableStateOf<Job?>(null) }
    var showSocialCamera by remember { mutableStateOf(false) }
    var cameraAudioEnabled by remember { mutableStateOf(false) }
    var cameraStorageEnabled by remember { mutableStateOf(android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) }
    var pickerTarget by remember { mutableStateOf("post") }
    var activeStory by remember { mutableStateOf<SocialStory?>(null) }
    var videoToPlay by remember { mutableStateOf<Pair<String, String>?>(null) }
    var videoFeedEntries by remember { mutableStateOf<List<SocialVideoFeedEntry>>(emptyList()) }
    var videoFeedIndex by remember { mutableIntStateOf(0) }
    var showSocialVideoFeed by remember { mutableStateOf(false) }
    var savedVideos by remember { mutableStateOf<List<SocialPost>>(emptyList()) }
    var commentsTarget by remember { mutableStateOf<SocialPost?>(null) }
    var showCreatePost by remember { mutableStateOf(false) }
    var showEditProfile by remember { mutableStateOf(false) }
    var editDisplayName by remember { mutableStateOf("") }
    var editUsername by remember { mutableStateOf("") }
    var editBio by remember { mutableStateOf("") }
    var isSavingProfile by remember { mutableStateOf(false) }
    var isUploadingMedia by remember { mutableStateOf(false) }
    var isLoading by remember { mutableStateOf(true) }
    var isRefreshing by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    val likedPosts = remember { mutableStateMapOf<String, Boolean>() }
    val savedVideoKeys = remember { mutableStateMapOf<String, Boolean>() }
    val likePending = remember { mutableStateMapOf<String, Boolean>() }
    val savePending = remember { mutableStateMapOf<String, Boolean>() }

    fun preparePostMediaSelection(candidates: List<Uri>) {
        val unique = candidates.distinct()
        if (unique.size > SocialMediaUploadLimits.MAX_SELECTED_MEDIA_PER_POST) {
            postUploadError = "No se agregaron los archivos nuevos: puedes seleccionar hasta ${SocialMediaUploadLimits.MAX_SELECTED_MEDIA_PER_POST} originales. Quita originales seleccionados antes de volver a elegirlos."
            return
        }
        selectedPostOriginalUris = unique
        postMediaPreparationGeneration += 1
        val generation = postMediaPreparationGeneration
        postMediaPreparationJob?.cancel()
        val oldGenerated = generatedPostClipFiles.toList()
        postMediaPreflightError = null
        postUploadError = null
        errorMessage = null
        if (unique.isEmpty()) {
            oldGenerated.forEach { it.delete() }
            generatedPostClipFiles.clear()
            newPostMediaUris = emptyList()
            postSplitSummary = null
            isPreparingPostMedia = false
            postMediaPreparationJob = null
            return
        }
        isPreparingPostMedia = true
        newPostMediaUris = emptyList()
        postSplitSummary = null
        postMediaPreparationJob = scope.launch {
            try {
                val prepared = SocialVideoAutoSplitter(context).prepare(unique)
                if (generation != postMediaPreparationGeneration) {
                    prepared.generatedFiles.forEach { it.delete() }
                    return@launch
                }
                val selectedOutputUris = prepared.uploads.map { it.uri.toString() }.toSet()
                val retainedOld = oldGenerated.filter { Uri.fromFile(it).toString() in selectedOutputUris }
                (oldGenerated - retainedOld.toSet()).forEach { it.delete() }
                generatedPostClipFiles.clear()
                generatedPostClipFiles.addAll((retainedOld + prepared.generatedFiles).distinct())
                newPostMediaUris = prepared.uploads.map { it.uri }
                postMediaPreflightError = null
                postUploadError = null
                postSplitSummary = prepared.splitVideoNames.takeIf { it.isNotEmpty() }?.let { names ->
                    "${unique.size} originales → ${prepared.uploads.size} archivos preparados (${prepared.generatedFiles.size} fragmentos generados). Videos divididos: ${names.joinToString().take(180)}. Se conservaron todos los segmentos y su orden; los originales siguen intactos."
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                if (generation == postMediaPreparationGeneration) {
                    val retainedOld = oldGenerated.filter { file -> unique.any { it.toString() == Uri.fromFile(file).toString() } }
                    (oldGenerated - retainedOld.toSet()).forEach { it.delete() }
                    generatedPostClipFiles.clear()
                    generatedPostClipFiles.addAll(retainedOld)
                    newPostMediaUris = emptyList()
                    postSplitSummary = null
                    postMediaPreflightError = error.message ?: "No se pudieron preparar los archivos seleccionados."
                }
            } finally {
                if (generation == postMediaPreparationGeneration) {
                    isPreparingPostMedia = false
                    postMediaPreparationJob = null
                }
            }
        }
    }

    fun cleanPostSplitCache() {
        generatedPostClipFiles.forEach { it.delete() }
        generatedPostClipFiles.clear()
        File(context.cacheDir, "social-post-splits").listFiles()
            ?.filter { it.name.startsWith("social-part-") && it.extension.equals("mp4", ignoreCase = true) }
            ?.forEach { it.delete() }
    }

    fun discardPostDraft() {
        postMediaPreparationGeneration += 1
        postMediaPreparationJob?.cancel()
        postMediaPreparationJob = null
        cleanPostSplitCache()
        selectedPostOriginalUris = emptyList()
        newPostMediaUris = emptyList()
        newPostText = ""
        postMediaPreflightError = null
        postUploadError = null
        postSplitSummary = null
        isPreparingPostMedia = false
        showCreatePost = false
    }

    DisposableEffect(Unit) {
        onDispose {
            postMediaPreparationJob?.cancel()
            generatedPostClipFiles.forEach { it.delete() }
            File(context.cacheDir, "social-post-splits").listFiles()
                ?.filter { it.name.startsWith("social-part-") && it.extension.equals("mp4", ignoreCase = true) }
                ?.forEach { it.delete() }
        }
    }

    val mediaPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickVisualMedia()
    ) { uri ->
        if (uri != null) {
            if (pickerTarget == "story") {
                val current = myProfile
                if (current != null) {
                    scope.launch {
                        isUploadingMedia = true
                        try {
                            val mimeType = context.contentResolver.getType(uri) ?: "image/jpeg"
                            repository.createStory(current, uri, mimeType)
                            stories = repository.loadStories()
                            errorMessage = null
                        } catch (error: Exception) {
                            errorMessage = error.message ?: "No se pudo subir la historia."
                        } finally {
                            isUploadingMedia = false
                        }
                    }
                }
            } else {
                preparePostMediaSelection(selectedPostOriginalUris + uri)
            }
        }
    }

    val multiMediaPicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.PickMultipleVisualMedia(maxItems = SocialMediaUploadLimits.MAX_SELECTED_MEDIA_PER_POST)
    ) { uris ->
        if (showCreatePost && uris.isNotEmpty()) preparePostMediaSelection(selectedPostOriginalUris + uris)
    }

    val cameraPermissionLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.RequestMultiplePermissions()
    ) { result ->
        val cameraGranted = result[android.Manifest.permission.CAMERA] == true ||
            context.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        cameraAudioEnabled = result[android.Manifest.permission.RECORD_AUDIO] == true ||
            context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
        cameraStorageEnabled = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q ||
            result[android.Manifest.permission.WRITE_EXTERNAL_STORAGE] == true ||
            context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraGranted) showSocialCamera = true else errorMessage = "Se necesita permiso de cámara para tomar una foto o grabar un video."
    }

    fun requestSocialCamera() {
        val cameraGranted = context.checkSelfPermission(android.Manifest.permission.CAMERA) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val audioGranted = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED
        val storageGranted = android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q ||
            context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == android.content.pm.PackageManager.PERMISSION_GRANTED
        if (cameraGranted && audioGranted && storageGranted) {
            cameraAudioEnabled = true
            cameraStorageEnabled = true
            showSocialCamera = true
        } else {
            val permissions = mutableListOf(android.Manifest.permission.CAMERA, android.Manifest.permission.RECORD_AUDIO)
            if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) {
                permissions += android.Manifest.permission.WRITE_EXTERNAL_STORAGE
            }
            cameraPermissionLauncher.launch(permissions.toTypedArray())
        }
    }

    fun postKey(post: SocialPost) = "${post.ownerUid}:${post.id}"

    suspend fun refreshFeed() {
        socialDiagnostic("feed_load_start")
        val items = repository.loadFeed(followingOnly = selectedSection == SocialSection.FOLLOWING)
        feed = items
        socialDiagnostic("feed_load_success", count = items.size)
        items.forEach { post ->
            val key = postKey(post)
            likedPosts[key] = runCatching { repository.likedByCurrentUser(post) }.getOrDefault(false)
            if (post.containsVideo) {
                savedVideoKeys[key] = runCatching { repository.isVideoSaved(post) }.getOrDefault(false)
            }
        }
    }

    fun openSocialVideoFeed(source: List<SocialPost>, selected: SocialPost, selectedMediaIndex: Int) {
        val entries = SocialVideoFeedLogic.expandVideos(source)
        if (entries.isEmpty()) return
        videoFeedEntries = entries
        videoFeedIndex = SocialVideoFeedLogic.selectedEntryIndex(
            entries, selected.ownerUid, selected.id, selectedMediaIndex
        )
        showSocialVideoFeed = true
    }

    fun toggleLike(post: SocialPost) {
        val key = postKey(post)
        if (likePending[key] == true) return
        val next = likedPosts[key] != true
        likePending[key] = true
        scope.launch {
            runCatching { repository.setLiked(post, next) }
                .onSuccess { likedPosts[key] = next }
                .onFailure { errorMessage = "No se pudo guardar el like." }
            likePending.remove(key)
        }
    }

    fun toggleSavedVideo(post: SocialPost) {
        val key = postKey(post)
        if (savePending[key] == true) return
        val next = savedVideoKeys[key] != true
        savePending[key] = true
        scope.launch {
            runCatching { repository.setVideoSaved(post, next) }
                .onSuccess {
                    savedVideoKeys[key] = next
                    savedVideos = if (next) (listOf(post) + savedVideos.filterNot { postKey(it) == key })
                    else savedVideos.filterNot { postKey(it) == key }
                }
                .onFailure { errorMessage = "No se pudo actualizar Ver más tarde." }
            savePending.remove(key)
        }
    }

    LaunchedEffect(currentUser?.uid) {
        likedPosts.clear()
        savedVideoKeys.clear()
        savedVideos = emptyList()
        likePending.clear()
        savePending.clear()
        showSocialVideoFeed = false
        commentsTarget = null
        feed = emptyList()
        if (currentUser == null) {
            errorMessage = "Inicia sesión para usar Social."
            isLoading = false
            return@LaunchedEffect
        }
        isLoading = true
        errorMessage = null
        try {
            socialDiagnostic("profile_load_start")
            myProfile = repository.ensureCurrentProfile(
                displayNameHint = currentUser.displayName,
                emailHint = currentUser.email,
                avatarUrlHint = currentUser.avatarUrl
            )
            followRequests = repository.pendingFollowRequests()
            stories = repository.loadStories()
            socialDiagnostic("profile_load_success")
            isLoading = false
        } catch (error: Exception) {
            socialDiagnostic("profile_load_error", error = error)
            errorMessage = error.message ?: "No se pudo cargar tu perfil social."
            isLoading = false
        }
    }

    LaunchedEffect(selectedSection, myProfile?.uid) {
        if (myProfile == null) return@LaunchedEffect
        try {
            when (selectedSection) {
                SocialSection.FOR_YOU, SocialSection.FOLLOWING, SocialSection.VIDEOS -> refreshFeed()
                SocialSection.SAVED -> {
                    savedVideos = repository.loadSavedVideos()
                    savedVideos.forEach { post ->
                        savedVideoKeys[postKey(post)] = true
                        likedPosts[postKey(post)] = runCatching { repository.likedByCurrentUser(post) }.getOrDefault(false)
                    }
                }
                else -> Unit
            }
            errorMessage = null
        } catch (error: Exception) {
            socialDiagnostic("feed_load_error", error = error)
            errorMessage = "No se pudo cargar el contenido de Social. Verifica la conexión y las reglas de Social."
        }
    }

    LaunchedEffect(searchQuery, selectedSection) {
        if (selectedSection != SocialSection.SEARCH) return@LaunchedEffect
        delay(250)
        if (searchQuery.isBlank()) {
            searchResults = emptyList()
        } else {
            try {
                searchResults = repository.searchProfiles(searchQuery)
                val ownUid = myProfile?.uid
                val statuses = mutableMapOf<String, String>()
                for (target in searchResults) {
                    statuses[target.uid] = if (target.uid == ownUid) "self" else repository.followStatus(target.uid).orEmpty()
                }
                followedState = statuses
            } catch (error: Exception) {
                errorMessage = "No se pudo buscar perfiles."
            }
        }
    }

    BackHandler(enabled = viewingProfile != null) {
        viewingProfile = null
        profilePosts = emptyList()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(Color(0xFF080D19))
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 12.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                IconButton(onClick = if (viewingProfile != null) {
                    { viewingProfile = null; profilePosts = emptyList() }
                } else onBack) {
                    Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Volver", tint = Color.White)
                }
                Column {
                    Text("Social", color = Color.White, fontSize = 22.sp, fontWeight = FontWeight.Bold)
                    Text("Tu comunidad en OmniStudio", color = Color(0xFF94A3B8), fontSize = 11.sp)
                }
            }
            Row {
                IconButton(
                    enabled = !isRefreshing,
                    onClick = {
                        scope.launch {
                            isRefreshing = true
                            try {
                                if (selectedSection == SocialSection.SAVED) {
                                    savedVideos = repository.loadSavedVideos()
                                    savedVideos.forEach { post ->
                                        savedVideoKeys[postKey(post)] = true
                                        likedPosts[postKey(post)] = runCatching { repository.likedByCurrentUser(post) }.getOrDefault(false)
                                    }
                                } else if (selectedSection != SocialSection.SEARCH && selectedSection != SocialSection.PROFILE) {
                                    refreshFeed()
                                }
                                stories = repository.loadStories()
                                errorMessage = null
                            } catch (error: Exception) {
                                errorMessage = "No se pudo actualizar: ${error.message ?: "error desconocido"}"
                            } finally {
                                isRefreshing = false
                            }
                        }
                    }
                ) {
                    if (isRefreshing) {
                        CircularProgressIndicator(
                            modifier = Modifier.size(18.dp),
                            strokeWidth = 2.dp,
                            color = Color(0xFFCBD5E1)
                        )
                    } else {
                        Icon(Icons.Default.Refresh, contentDescription = "Actualizar feed e historias", tint = Color(0xFFCBD5E1))
                    }
                }
                IconButton(
                    onClick = { showCreatePost = true },
                    modifier = Modifier.testTag("social_create_post")
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Crear publicación", tint = Color(0xFFF472B6))
                }
            }
        }

        if (viewingProfile == null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .horizontalScroll(androidx.compose.foundation.rememberScrollState())
                    .padding(horizontal = 12.dp, vertical = 4.dp),
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SocialSection.values().forEach { section ->
                    val selected = selectedSection == section
                    Surface(
                        color = if (selected) Color(0xFF4C1D3D) else Color(0xFF151C2C),
                        shape = RoundedCornerShape(18.dp),
                        modifier = Modifier
                            .clip(RoundedCornerShape(18.dp))
                            .clickable { selectedSection = section }
                    ) {
                        Text(
                            text = section.label,
                            color = if (selected) Color(0xFFF9A8D4) else Color(0xFFCBD5E1),
                            fontSize = 12.sp,
                            fontWeight = if (selected) FontWeight.Bold else FontWeight.Medium,
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 10.dp)
                                .testTag("social_tab_${section.name.lowercase()}")
                        )
                    }
                }
            }
        }

        errorMessage?.let { message ->
            Surface(
                color = Color(0xFF3B1D2A),
                shape = RoundedCornerShape(12.dp),
                modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 6.dp)
            ) {
                Text(message, color = Color(0xFFFDA4AF), fontSize = 12.sp, modifier = Modifier.padding(10.dp))
            }
        }

        if (isLoading) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = Color(0xFFE1306C))
            }
        } else if (viewingProfile != null) {
            ViewedProfileContent(
                profile = viewingProfile!!,
                posts = profilePosts,
                repository = repository,
                followStatus = followedState[viewingProfile!!.uid].orEmpty(),
                onFollow = {
                    viewingProfile?.let { target ->
                        scope.launch {
                            try {
                                if (followedState[target.uid] == "accepted" || followedState[target.uid] == "pending") {
                                    repository.unfollow(target.uid)
                                    followedState = followedState + (target.uid to "")
                                } else {
                                    repository.follow(target, myProfile ?: error("Tu perfil no está disponible."))
                                    followedState = followedState + (target.uid to if (target.isPrivate) "pending" else "accepted")
                                }
                            } catch (error: Exception) {
                                errorMessage = error.message ?: "No se pudo actualizar el seguimiento."
                            }
                        }
                    }
                }
            )
        } else {
            when (selectedSection) {
                SocialSection.FOR_YOU, SocialSection.FOLLOWING, SocialSection.VIDEOS -> {
                    val displayPosts = if (selectedSection == SocialSection.VIDEOS) feed.filter { it.containsVideo } else feed
                    LazyColumn(
                        modifier = Modifier.fillMaxSize(),
                        verticalArrangement = Arrangement.spacedBy(10.dp)
                    ) {
                        if (selectedSection == SocialSection.FOR_YOU) {
                            item {
                                StoriesPlaceholder(
                                    profile = myProfile,
                                    stories = stories,
                                    onAddStory = {
                                        pickerTarget = "story"
                                        mediaPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                                    },
                                    onOpenStory = { story ->
                                        scope.launch {
                                            try {
                                                val url = repository.signedMediaUrl(story.mediaPath, "story", story.id)
                                                activeStory = story.copy(mediaUrl = url)
                                            } catch (error: Exception) {
                                                errorMessage = "No se pudo abrir esta historia privada."
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        if (displayPosts.isEmpty()) {
                            item {
                                if (selectedSection == SocialSection.VIDEOS) {
                                    Text("Todavía no hay videos disponibles.", color = Color(0xFF94A3B8), modifier = Modifier.padding(24.dp))
                                } else EmptySocialFeed(isFollowing = selectedSection == SocialSection.FOLLOWING, onCreate = { showCreatePost = true })
                            }
                        } else {
                            items(displayPosts, key = { postKey(it) }) { post ->
                                SocialPostCard(
                                    post = post,
                                    repository = repository,
                                    liked = likedPosts[postKey(post)] == true,
                                    onLike = { toggleLike(post) },
                                    onVideoClick = { selected, mediaIndex -> openSocialVideoFeed(displayPosts, selected, mediaIndex) },
                                    onAuthorClick = {
                                        scope.launch {
                                            try {
                                                val loadedProfile = repository.getProfile(post.ownerUid)
                                                viewingProfile = loadedProfile ?: SocialProfile(
                                                    uid = post.ownerUid,
                                                    username = post.username,
                                                    displayName = post.displayName,
                                                    avatarUrl = post.avatarUrl
                                                )
                                                profilePosts = repository.loadProfilePosts(post.ownerUid)
                                                followedState = followedState + (post.ownerUid to repository.followStatus(post.ownerUid).orEmpty())
                                            } catch (error: Exception) {
                                                errorMessage = "No se pudo abrir ese perfil."
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        item { Spacer(Modifier.size(12.dp)) }
                    }
                }

                SocialSection.SAVED -> {
                    LazyColumn(modifier = Modifier.fillMaxSize(), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        if (savedVideos.isEmpty()) {
                            item { Text("Los videos que guardes aparecerán aquí.", color = Color(0xFF94A3B8), modifier = Modifier.padding(24.dp)) }
                        } else {
                            items(savedVideos, key = { postKey(it) }) { post ->
                                SocialPostCard(
                                    post = post,
                                    repository = repository,
                                    liked = likedPosts[postKey(post)] == true,
                                    onLike = { toggleLike(post) },
                                    onVideoClick = { selected, mediaIndex -> openSocialVideoFeed(savedVideos, selected, mediaIndex) },
                                    onAuthorClick = {}
                                )
                            }
                        }
                    }
                }

                SocialSection.SEARCH -> {
                    Column(Modifier.fillMaxSize()) {
                        OutlinedTextField(
                            value = searchQuery,
                            onValueChange = { searchQuery = it },
                            modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 8.dp)
                                .testTag("social_search_query"),
                            leadingIcon = { Icon(Icons.Default.Search, contentDescription = null, tint = Color(0xFFF472B6)) },
                            placeholder = { Text("Buscar personas por nombre o @usuario") },
                            singleLine = true
                        )
                        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
                            items(searchResults, key = { it.uid }) { target ->
                                SearchProfileRow(
                                    profile = target,
                                    isSelf = target.uid == myProfile?.uid,
                                    followStatus = followedState[target.uid].orEmpty(),
                                    onOpen = {
                                        scope.launch {
                                            val loaded = runCatching { repository.getProfile(target.uid) }.getOrNull()
                                            viewingProfile = loaded ?: target
                                            profilePosts = runCatching { repository.loadProfilePosts(target.uid) }.getOrDefault(emptyList())
                                        }
                                    },
                                    onFollow = {
                                        scope.launch {
                                            try {
                                                if (followedState[target.uid] == "accepted" || followedState[target.uid] == "pending") {
                                                    repository.unfollow(target.uid)
                                                    followedState = followedState + (target.uid to "")
                                                } else {
                                                    repository.follow(target, myProfile ?: error("Tu perfil no está disponible."))
                                                    followedState = followedState + (target.uid to if (target.isPrivate) "pending" else "accepted")
                                                }
                                            } catch (error: Exception) {
                                                errorMessage = error.message ?: "No se pudo seguir ese perfil."
                                            }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }

                SocialSection.PROFILE -> {
                    val myPosts = remember(feed, myProfile?.uid) { feed.filter { it.ownerUid == myProfile?.uid } }
                    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        item {
                            MyProfileCard(
                                profile = myProfile,
                                onEdit = {
                                    myProfile?.let { profile ->
                                        editDisplayName = profile.displayName
                                        editUsername = profile.username
                                        editBio = profile.bio
                                        showEditProfile = true
                                    }
                                },
                                onVisibilityChanged = { makePublic ->
                                    myProfile?.let { current ->
                                        scope.launch {
                                            try {
                                                myProfile = repository.updateProfile(
                                                    current = current,
                                                    displayName = current.displayName,
                                                    bio = current.bio,
                                                    visibility = if (makePublic) "public" else "private"
                                                )
                                                followRequests = repository.pendingFollowRequests()
                                            } catch (error: Exception) {
                                                errorMessage = "No se pudo cambiar la privacidad: ${error.message ?: "error desconocido"}"
                                            }
                                        }
                                    }
                                }
                            )
                        }
                        if (followRequests.isNotEmpty()) {
                            item {
                                FollowRequestsCard(
                                    requests = followRequests,
                                    onAccept = { request ->
                                        scope.launch {
                                            runCatching { repository.acceptFollowRequest(request.uid) }
                                                .onSuccess { followRequests = repository.pendingFollowRequests() }
                                                .onFailure { errorMessage = "No se pudo aceptar la solicitud." }
                                        }
                                    }
                                )
                            }
                        }
                        if (myPosts.isEmpty()) item { EmptySocialFeed(isFollowing = false, onCreate = { showCreatePost = true }) }
                        items(myPosts, key = { postKey(it) }) { post ->
                            SocialPostCard(
                                post = post,
                                repository = repository,
                                liked = likedPosts[postKey(post)] == true,
                                onLike = { toggleLike(post) },
                                onVideoClick = { selected, mediaIndex -> openSocialVideoFeed(myPosts, selected, mediaIndex) },
                                onAuthorClick = {}
                            )
                        }
                    }
                }
            }
        }
    }

    if (showSocialVideoFeed && videoFeedEntries.isNotEmpty()) {
        SocialVideoFeedDialog(
            entries = videoFeedEntries,
            initialIndex = videoFeedIndex,
            isLiked = { likedPosts[postKey(it)] == true },
            isSaved = { savedVideoKeys[postKey(it)] == true },
            likeBusy = { likePending[postKey(it)] == true },
            saveBusy = { savePending[postKey(it)] == true },
            onLike = { toggleLike(it) },
            onSave = { toggleSavedVideo(it) },
            onComments = { commentsTarget = it },
            onPositionChanged = { videoFeedIndex = it },
            onDismiss = { showSocialVideoFeed = false }
        )
    }

    commentsTarget?.let { post ->
        SocialCommentsDialog(
            post = post,
            repository = repository,
            onDismiss = { commentsTarget = null },
            onError = { errorMessage = it }
        )
    }

    activeStory?.let { story ->
        Dialog(onDismissRequest = { activeStory = null }, properties = DialogProperties(usePlatformDefaultWidth = false)) {
            Surface(color = Color(0xFF05070D), modifier = Modifier.fillMaxSize()) {
                Box(Modifier.fillMaxSize()) {
                    if (story.mediaType == "video") {
                        VideoPlayer(
                            videoUrl = story.mediaUrl,
                            title = "Historia de @${story.username}",
                            showActionButtons = false,
                            onLaunchStandardVideo = { url, title -> videoToPlay = url to title }
                        )
                    } else {
                        AsyncImage(
                            model = story.mediaUrl,
                            contentDescription = "Historia de ${story.displayName}",
                            contentScale = ContentScale.Fit,
                            modifier = Modifier.fillMaxSize()
                        )
                    }
                    TextButton(onClick = { activeStory = null }, modifier = Modifier.align(Alignment.TopEnd).padding(12.dp)) {
                        Text("Cerrar", color = Color.White)
                    }
                }
            }
        }
    }

    videoToPlay?.let { (url, title) ->
        StandardVideoPlayerDialog(videoUrl = url, title = title, onDismiss = { videoToPlay = null })
    }

    if (showEditProfile) {
        AlertDialog(
            onDismissRequest = { if (!isSavingProfile) showEditProfile = false },
            containerColor = Color(0xFF151C2C),
            title = { Text("Editar perfil", color = Color.White, fontWeight = FontWeight.Bold) },
            text = {
                Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    OutlinedTextField(
                        value = editDisplayName,
                        onValueChange = { editDisplayName = it.take(48) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Nombre visible") },
                        singleLine = true
                    )
                    OutlinedTextField(
                        value = editUsername,
                        onValueChange = { value ->
                            editUsername = value.lowercase(Locale.ROOT)
                                .filter { it in 'a'..'z' || it in '0'..'9' || it == '_' }
                                .take(20)
                        },
                        modifier = Modifier.fillMaxWidth().testTag("social_edit_username"),
                        label = { Text("Nombre de usuario (sin @)") },
                        singleLine = true
                    )
                    Text("Si ya está ocupado, se agregará un número para hacerlo único.", color = Color(0xFF94A3B8), fontSize = 11.sp)
                    OutlinedTextField(
                        value = editBio,
                        onValueChange = { editBio = it.take(160) },
                        modifier = Modifier.fillMaxWidth(),
                        label = { Text("Descripción") },
                        maxLines = 3
                    )
                }
            },
            confirmButton = {
                Button(
                    enabled = editUsername.length >= 3 && !isSavingProfile,
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE1306C)),
                    onClick = {
                        val current = myProfile ?: return@Button
                        scope.launch {
                            isSavingProfile = true
                            try {
                                val requestedUsername = editUsername.trim().removePrefix("@").lowercase(Locale.ROOT)
                                val updated = repository.updateProfile(
                                    current = current,
                                    displayName = editDisplayName,
                                    bio = editBio,
                                    visibility = current.visibility,
                                    username = requestedUsername
                                )
                                myProfile = updated
                                showEditProfile = false
                                refreshFeed()
                                profilePosts = repository.loadProfilePosts(current.uid)
                                errorMessage = if (updated.username != requestedUsername) {
                                    "Ese nombre ya estaba usado; se asignó @${updated.username}."
                                } else null
                            } catch (error: Exception) {
                                errorMessage = error.message ?: "No se pudo guardar el perfil."
                            } finally {
                                isSavingProfile = false
                            }
                        }
                    }
                ) { Text(if (isSavingProfile) "Guardando…" else "Guardar") }
            },
            dismissButton = { TextButton(onClick = { showEditProfile = false }, enabled = !isSavingProfile) { Text("Cancelar") } }
        )
    }

    if (showCreatePost) {
        AlertDialog(
            onDismissRequest = { if (!isPublishingPost) discardPostDraft() },
            containerColor = Color(0xFF151C2C),
            title = { Text("Nueva publicación", color = Color.White, fontWeight = FontWeight.Bold) },
            text = {
                Column {
                    Text("Comparte una idea con tu comunidad. Puedes usar #temas para personalizar recomendaciones.", color = Color(0xFFCBD5E1), fontSize = 12.sp)
                    Spacer(Modifier.size(10.dp))
                    OutlinedTextField(
                        value = newPostText,
                        onValueChange = { newPostText = it.take(2200) },
                        modifier = Modifier.fillMaxWidth().testTag("social_new_post_text"),
                        placeholder = { Text("¿Qué quieres compartir?") },
                        minLines = 3,
                        maxLines = 6
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        TextButton(
                            enabled = !isPreparingPostMedia && !isPublishingPost,
                            onClick = {
                                pickerTarget = "post"
                                multiMediaPicker.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageAndVideo))
                            }
                        ) {
                            Icon(Icons.Default.Add, contentDescription = null, tint = Color(0xFFF472B6), modifier = Modifier.size(18.dp))
                            Text(if (selectedPostOriginalUris.isEmpty()) "Elegir fotos, GIFs o videos" else "Añadir más medios", color = Color(0xFFF472B6))
                        }
                        TextButton(onClick = { requestSocialCamera() }, enabled = !isPreparingPostMedia && !isPublishingPost) {
                            Text("Cámara", color = Color(0xFFF472B6))
                        }
                    }
                    if (selectedPostOriginalUris.isNotEmpty()) {
                        Text(
                            if (isPreparingPostMedia) {
                                "${selectedPostOriginalUris.size}/${SocialMediaUploadLimits.MAX_SELECTED_MEDIA_PER_POST} originales · preparando archivos…"
                            } else {
                                "${selectedPostOriginalUris.size}/${SocialMediaUploadLimits.MAX_SELECTED_MEDIA_PER_POST} originales · ${newPostMediaUris.size}/${SocialMediaUploadLimits.MAX_PREPARED_MEDIA_PER_POST} archivos preparados · máximo 50 MiB cada uno"
                            },
                            color = Color(0xFF94A3B8), fontSize = 11.sp
                        )
                        LazyRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            itemsIndexed(selectedPostOriginalUris) { index, uri ->
                                Row(
                                    modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Color(0xFF202A3A)).padding(start = 8.dp, end = 2.dp),
                                    verticalAlignment = Alignment.CenterVertically
                                ) {
                                    Text("${index + 1}. ${context.contentResolver.getType(uri)?.substringBefore('/') ?: if (uri.path?.endsWith(".mp4", true) == true) "video" else "media"}", color = Color(0xFFCBD5E1), fontSize = 11.sp)
                                    IconButton(
                                        onClick = {
                                            preparePostMediaSelection(selectedPostOriginalUris.filterIndexed { itemIndex, _ -> itemIndex != index })
                                        },
                                        modifier = Modifier.size(30.dp),
                                        enabled = !isPreparingPostMedia && !isPublishingPost
                                    ) {
                                        Icon(Icons.Default.Close, contentDescription = "Quitar original", tint = Color(0xFFCBD5E1), modifier = Modifier.size(15.dp))
                                    }
                                }
                            }
                        }
                    }
                    if (isPreparingPostMedia) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            CircularProgressIndicator(modifier = Modifier.size(16.dp), strokeWidth = 2.dp, color = Color(0xFFF472B6))
                            Text("Preparando ${selectedPostOriginalUris.size} originales; los videos grandes se dividen en clips menores de 50 MiB. Se conservarán todos los segmentos y el orden.", color = Color(0xFFCBD5E1), fontSize = 11.sp)
                        }
                    }
                    postSplitSummary?.let { Text(it, color = Color(0xFF86EFAC), fontSize = 11.sp) }
                    if (isPublishingPost) {
                        Text("Subiendo ${newPostMediaUris.size} archivos preparados desde ${selectedPostOriginalUris.size} originales…", color = Color(0xFFCBD5E1), fontSize = 11.sp)
                    }
                    postMediaPreflightError?.let { Text(it, color = Color(0xFFFCA5A5), fontSize = 11.sp) }
                    postUploadError?.let { Text(it, color = Color(0xFFFCA5A5), fontSize = 11.sp) }
                }
            },
            confirmButton = {
                Button(
                    modifier = Modifier.testTag("social_publish_post"),
                    enabled = SocialPostPublishPolicy.canPublish(
                        hasCaption = newPostText.isNotBlank(),
                        mediaCount = newPostMediaUris.size,
                        isPreparing = isPreparingPostMedia,
                        isUploading = isPublishingPost,
                        hasPreflightError = postMediaPreflightError != null
                    ),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE1306C)),
                    onClick = {
                        val current = myProfile ?: return@Button
                        postUploadError = null
                        scope.launch {
                            isPublishingPost = true
                            try {
                                if (newPostMediaUris.isEmpty()) {
                                    repository.createTextPost(current, newPostText)
                                } else {
                                    val uploads = newPostMediaUris.map { uri ->
                                        SocialMediaUpload(uri, context.contentResolver.getType(uri) ?: if (uri.path?.endsWith(".mp4", true) == true) "video/mp4" else "image/jpeg")
                                    }
                                    repository.createMediaPost(current, newPostText, uploads)
                                }
                                cleanPostSplitCache()
                                newPostText = ""
                                selectedPostOriginalUris = emptyList()
                                newPostMediaUris = emptyList()
                                postMediaPreflightError = null
                                postUploadError = null
                                postSplitSummary = null
                                showCreatePost = false
                                selectedSection = SocialSection.FOR_YOU
                                refreshFeed()
                                errorMessage = null
                            } catch (error: Exception) {
                                postUploadError = error.message ?: "No se pudo publicar. Puedes corregir o reintentar."
                                errorMessage = null
                            } finally {
                                isPublishingPost = false
                            }
                        }
                    }
                ) { Text(when { isPreparingPostMedia -> "Preparando…"; isPublishingPost -> "Publicando…"; else -> "Publicar" }) }
            },
            dismissButton = { TextButton(onClick = { discardPostDraft() }, enabled = !isPublishingPost) { Text("Cancelar") } }
        )
    }

    if (showSocialCamera) {
        SocialCameraDialog(
            enableAudio = cameraAudioEnabled,
            videoStorageAllowed = cameraStorageEnabled,
            onDismiss = { showSocialCamera = false },
            onCapture = { uri, _ ->
                preparePostMediaSelection(selectedPostOriginalUris + uri)
                showSocialCamera = false
            }
        )
    }

}

@Composable
private fun StoriesPlaceholder(
    profile: SocialProfile?,
    stories: List<SocialStory>,
    onAddStory: () -> Unit,
    onOpenStory: (SocialStory) -> Unit
) {
    val latestStories = stories
        .filter { it.ownerUid != profile?.uid }
        .groupBy { it.ownerUid }
        .values
        .mapNotNull { group -> group.maxByOrNull { it.createdAt } }
    Column(Modifier.fillMaxWidth().padding(top = 10.dp, bottom = 2.dp)) {
        Text("Historias · 24 horas", color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp))
        LazyRow(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp)
        ) {
            item {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable(onClick = onAddStory)) {
                    Box(contentAlignment = Alignment.BottomEnd) {
                        AvatarCircle(name = profile?.displayName ?: "Tú", color = Color(0xFFE1306C), size = 56, imageUrl = profile?.avatarUrl.orEmpty())
                        Surface(color = Color(0xFFE1306C), shape = CircleShape, modifier = Modifier.size(20.dp)) {
                            Icon(Icons.Default.Add, contentDescription = "Agregar historia", tint = Color.White, modifier = Modifier.padding(2.dp))
                        }
                    }
                    Text("Tu historia", color = Color(0xFFCBD5E1), fontSize = 10.sp, modifier = Modifier.padding(top = 4.dp))
                }
            }
            items(latestStories, key = { it.ownerUid }) { story ->
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.clickable { onOpenStory(story) }) {
                    AvatarCircle(name = story.displayName, color = Color(0xFFE1306C), size = 56, imageUrl = story.avatarUrl)
                    Text(story.username.take(12), color = Color(0xFFCBD5E1), fontSize = 10.sp, modifier = Modifier.padding(top = 4.dp))
                }
            }
        }
    }
}

@Composable
private fun SocialPostCard(
    post: SocialPost,
    repository: SocialRepository,
    liked: Boolean,
    onLike: () -> Unit,
    onVideoClick: ((SocialPost, Int) -> Unit)? = null,
    onAuthorClick: () -> Unit
) {
    val mediaItems = remember(post.mediaItems, post.mediaPath, post.mediaType) {
        post.mediaItems.ifEmpty {
            if (post.mediaPath.isBlank()) emptyList() else listOf(SocialPostMedia(post.mediaPath, post.mediaType))
        }
    }
    val signedMediaUrls by produceState(initialValue = List(mediaItems.size) { "" }, post.id, mediaItems) {
        value = mediaItems.mapIndexed { index, item ->
            socialDiagnostic("media_url_start", index = index, mediaType = item.mediaType)
            try {
                repository.signedMediaUrl(item.mediaPath, "post", post.id).also { url ->
                    socialDiagnostic(if (url.isBlank()) "media_url_empty" else "media_url_success", index = index, mediaType = item.mediaType)
                }
            } catch (error: CancellationException) {
                throw error
            } catch (error: Exception) {
                socialDiagnostic("media_url_error", index = index, mediaType = item.mediaType, error = error)
                ""
            }
        }
    }
    var videoToPlay by remember(post.id) { mutableStateOf<Pair<String, String>?>(null) }

    Surface(
        color = Color(0xFF111827),
        shape = RoundedCornerShape(18.dp),
        modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)
    ) {
        Column(Modifier.padding(14.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AvatarCircle(name = post.displayName, color = Color(0xFF7C3AED), size = 40, imageUrl = post.avatarUrl)
                Column(Modifier.weight(1f).padding(start = 10.dp).clickable(onClick = onAuthorClick)) {
                    Text(post.displayName, color = Color.White, fontSize = 13.sp, fontWeight = FontWeight.Bold, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    Text("@${post.username}", color = Color(0xFF94A3B8), fontSize = 10.sp)
                }
                Text(relativeTime(post.createdAt), color = Color(0xFF64748B), fontSize = 10.sp)
            }
            if (post.caption.isNotBlank()) {
                Text(post.caption, color = Color(0xFFE2E8F0), fontSize = 14.sp, lineHeight = 20.sp, modifier = Modifier.padding(top = 12.dp))
            }
            if (mediaItems.isNotEmpty()) {
                LazyRow(
                    modifier = Modifier.fillMaxWidth().padding(top = 10.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    itemsIndexed(mediaItems) { index, item ->
                        val url = signedMediaUrls.getOrElse(index) { "" }
                        Box(Modifier.width(300.dp).heightIn(max = 340.dp), contentAlignment = Alignment.Center) {
                            if (url.isBlank()) {
                                CircularProgressIndicator(color = Color(0xFFE1306C), modifier = Modifier.size(22.dp), strokeWidth = 2.dp)
                            } else if (item.mediaType == "video") {
                                VideoPlayer(
                                    videoUrl = url,
                                    title = "Video de @${post.username}",
                                    showActionButtons = false,
                                    modifier = Modifier.fillMaxWidth(),
                                    onDiagnosticEvent = { event, code, errorClass ->
                                        socialDiagnostic(event, index = index, mediaType = item.mediaType, code = code, errorClass = errorClass)
                                    },
                                    onLaunchStandardVideo = { videoUrl, title ->
                                        if (onVideoClick != null) onVideoClick(post, index) else videoToPlay = videoUrl to title
                                    }
                                )
                            } else {
                                AsyncImage(
                                    model = url,
                                    contentDescription = "Publicación de ${post.displayName}",
                                    contentScale = ContentScale.Fit,
                                    modifier = Modifier.fillMaxWidth().heightIn(max = 340.dp),
                                    onLoading = { socialDiagnostic("image_render_start", index = index, mediaType = item.mediaType) },
                                    onSuccess = { socialDiagnostic("image_render_success", index = index, mediaType = item.mediaType) },
                                    onError = { state ->
                                        socialDiagnostic("image_render_error", index = index, mediaType = item.mediaType, error = state.result.throwable)
                                    }
                                )
                            }
                        }
                    }
                }
                if (mediaItems.size > 1) {
                    Text("${mediaItems.size} archivos · desliza para verlos", color = Color(0xFF94A3B8), fontSize = 10.sp, modifier = Modifier.padding(top = 4.dp))
                }
            }
            if (post.topics.isNotEmpty()) {
                Text(post.topics.joinToString("  ") { "#$it" }, color = Color(0xFFF472B6), fontSize = 11.sp, modifier = Modifier.padding(top = 8.dp))
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(top = 4.dp)) {
                IconButton(onClick = onLike, modifier = Modifier.testTag("social_like_${post.id}")) {
                    Icon(
                        imageVector = if (liked) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                        contentDescription = if (liked) "Quitar me gusta" else "Me gusta",
                        tint = if (liked) Color(0xFFE1306C) else Color(0xFFCBD5E1)
                    )
                }
                Text(if (liked) "Te gusta" else "Me gusta", color = if (liked) Color(0xFFF472B6) else Color(0xFFCBD5E1), fontSize = 12.sp)
                Spacer(Modifier.weight(1f))
                if (post.mediaType != "text") Text("Multimedia", color = Color(0xFF94A3B8), fontSize = 10.sp)
            }
        }
    }
    videoToPlay?.let { (url, title) ->
        StandardVideoPlayerDialog(videoUrl = url, title = title, onDismiss = { videoToPlay = null })
    }
}

@Composable
private fun SocialVideoFeedDialog(
    entries: List<SocialVideoFeedEntry>,
    initialIndex: Int,
    isLiked: (SocialPost) -> Boolean,
    isSaved: (SocialPost) -> Boolean,
    likeBusy: (SocialPost) -> Boolean,
    saveBusy: (SocialPost) -> Boolean,
    onLike: (SocialPost) -> Unit,
    onSave: (SocialPost) -> Unit,
    onComments: (SocialPost) -> Unit,
    onPositionChanged: (Int) -> Unit,
    onDismiss: () -> Unit
) {
    if (entries.isEmpty()) return
    var currentIndex by remember(entries, initialIndex) {
        mutableIntStateOf(initialIndex.coerceIn(0, entries.lastIndex))
    }
    val entry = entries[currentIndex]
    val post = entry.post
    val context = LocalContext.current
    val signedMediaUrl by produceState(initialValue = "", post.mediaPath, post.id, entry.mediaIndex, entry.media.mediaPath) {
        value = if (entry.media.mediaPath.isNotBlank()) {
            runCatching { SocialRepository(context).signedMediaUrl(entry.media.mediaPath, "post", post.id) }
                .getOrDefault("")
        } else post.mediaUrl
    }
    val density = LocalDensity.current
    val swipeThreshold = with(density) { 76.dp.toPx() }

    Dialog(
        onDismissRequest = onDismiss,
        properties = DialogProperties(usePlatformDefaultWidth = false)
    ) {
        Surface(color = Color.Black, modifier = Modifier.fillMaxSize().testTag("social_video_feed")) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .pointerInput(currentIndex, entries.size) {
                        var totalDrag = 0f
                        detectVerticalDragGestures(
                            onVerticalDrag = { _, dragAmount -> totalDrag += dragAmount },
                            onDragEnd = {
                                val direction = SocialVideoFeedLogic.swipeDirection(totalDrag, swipeThreshold)
                                val next = SocialVideoFeedLogic.adjacentIndex(currentIndex, entries.size, direction)
                                if (next != null) {
                                    currentIndex = next
                                    onPositionChanged(next)
                                }
                                totalDrag = 0f
                            },
                            onDragCancel = { totalDrag = 0f }
                        )
                    }
            ) {
                key(entry.stableKey, signedMediaUrl) {
                    if (signedMediaUrl.isBlank()) {
                        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = Color(0xFFE1306C))
                        }
                    } else {
                        SocialVideoSurface(videoUrl = signedMediaUrl)
                    }
                }

                Box(
                    Modifier.fillMaxSize().background(
                        Brush.verticalGradient(
                            colors = listOf(Color.Black.copy(alpha = 0.38f), Color.Transparent, Color.Black.copy(alpha = 0.68f))
                        )
                    )
                )

                IconButton(
                    onClick = onDismiss,
                    modifier = Modifier.align(Alignment.TopStart).padding(start = 10.dp, top = 12.dp).testTag("social_video_close")
                ) {
                    Icon(Icons.Default.Close, contentDescription = "Cerrar video", tint = Color.White)
                }
                Text(
                    text = "Videos · ${currentIndex + 1}/${entries.size}",
                    color = Color.White,
                    fontSize = 14.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.align(Alignment.TopCenter).padding(top = 24.dp)
                )

                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(3.dp),
                    modifier = Modifier.align(Alignment.CenterEnd).padding(end = 8.dp)
                ) {
                    IconButton(
                        enabled = !likeBusy(post),
                        onClick = { onLike(post) },
                        modifier = Modifier.testTag("social_video_like_${post.id}")
                    ) {
                        Icon(
                            imageVector = if (isLiked(post)) Icons.Default.Favorite else Icons.Default.FavoriteBorder,
                            contentDescription = if (isLiked(post)) "Quitar me gusta" else "Me gusta",
                            tint = if (isLiked(post)) Color(0xFFFF3B70) else Color.White,
                            modifier = Modifier.size(30.dp)
                        )
                    }
                    Text(if (isLiked(post)) "Te gusta" else "Me gusta", color = Color.White, fontSize = 10.sp)

                    IconButton(
                        onClick = { onComments(post) },
                        modifier = Modifier.padding(top = 10.dp).testTag("social_video_comments_${post.id}")
                    ) {
                        Icon(Icons.Default.Comment, contentDescription = "Ver y comentar", tint = Color.White, modifier = Modifier.size(28.dp))
                    }
                    Text("Comentar", color = Color.White, fontSize = 10.sp)

                    IconButton(
                        enabled = !saveBusy(post),
                        onClick = { onSave(post) },
                        modifier = Modifier.padding(top = 10.dp).testTag("social_video_save_${post.id}")
                    ) {
                        Icon(
                            imageVector = if (isSaved(post)) Icons.Default.Bookmark else Icons.Default.BookmarkBorder,
                            contentDescription = if (isSaved(post)) "Quitar de Ver más tarde" else "Guardar para Ver más tarde",
                            tint = if (isSaved(post)) Color(0xFFF9A8D4) else Color.White,
                            modifier = Modifier.size(29.dp)
                        )
                    }
                    Text(if (isSaved(post)) "Guardado" else "Ver más tarde", color = Color.White, fontSize = 10.sp)
                }

                Column(
                    modifier = Modifier.align(Alignment.BottomStart).fillMaxWidth().padding(start = 16.dp, end = 92.dp, bottom = 28.dp)
                ) {
                    Text("${post.displayName}  @${post.username}", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 14.sp, maxLines = 1, overflow = TextOverflow.Ellipsis)
                    if (post.caption.isNotBlank()) {
                        Text(post.caption, color = Color.White, fontSize = 13.sp, maxLines = 4, overflow = TextOverflow.Ellipsis, modifier = Modifier.padding(top = 5.dp))
                    }
                    if (post.topics.isNotEmpty()) {
                        Text(post.topics.joinToString("  ") { "#$it" }, color = Color(0xFFF9A8D4), fontSize = 11.sp, modifier = Modifier.padding(top = 5.dp))
                    }
                    Text("Desliza arriba o abajo para cambiar de video", color = Color.White.copy(alpha = 0.78f), fontSize = 10.sp, modifier = Modifier.padding(top = 9.dp))
                }
            }
        }
    }
}

@Composable
private fun SocialVideoSurface(videoUrl: String) {
    var isLoading by remember(videoUrl) { mutableStateOf(true) }
    var playbackError by remember(videoUrl) { mutableStateOf<String?>(null) }
    var videoView by remember(videoUrl) { mutableStateOf<SocialAspectFitVideoView?>(null) }

    DisposableEffect(videoUrl) {
        onDispose { runCatching { videoView?.stopPlayback() } }
    }

    Box(Modifier.fillMaxSize().background(Color.Black), contentAlignment = Alignment.Center) {
        AndroidView(
            factory = { ctx ->
                FrameLayout(ctx).apply {
                    setBackgroundColor(android.graphics.Color.BLACK)
                    val player = SocialAspectFitVideoView(ctx).apply {
                        setOnPreparedListener { mediaPlayer ->
                            updateSourceSize(mediaPlayer.videoWidth, mediaPlayer.videoHeight)
                            mediaPlayer.isLooping = true
                            isLoading = false
                            start()
                        }
                        setOnErrorListener { _, what, extra ->
                            isLoading = false
                            playbackError = "No se pudo reproducir este video ($what/$extra)."
                            true
                        }
                        try {
                            setVideoURI(Uri.parse(videoUrl))
                        } catch (error: Exception) {
                            isLoading = false
                            playbackError = error.localizedMessage ?: "No se pudo cargar el video."
                        }
                    }
                    videoView = player
                    addView(
                        player,
                        FrameLayout.LayoutParams(
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            ViewGroup.LayoutParams.WRAP_CONTENT,
                            Gravity.CENTER
                        )
                    )
                }
            },
            update = { frame ->
                videoView = (0 until frame.childCount).asSequence()
                    .mapNotNull { frame.getChildAt(it) as? SocialAspectFitVideoView }
                    .firstOrNull()
            },
            modifier = Modifier.fillMaxSize()
        )
        if (isLoading && playbackError == null) CircularProgressIndicator(color = Color.White)
        playbackError?.let { message ->
            Text(message, color = Color.White, modifier = Modifier.align(Alignment.Center).padding(24.dp))
        }
    }
}

private class SocialAspectFitVideoView(context: Context) : VideoView(context) {
    private var sourceWidth = 0
    private var sourceHeight = 0

    fun updateSourceSize(width: Int, height: Int) {
        sourceWidth = width
        sourceHeight = height
        requestLayout()
    }

    override fun onMeasure(widthMeasureSpec: Int, heightMeasureSpec: Int) {
        val maxWidth = MeasureSpec.getSize(widthMeasureSpec).coerceAtLeast(1)
        val maxHeight = MeasureSpec.getSize(heightMeasureSpec).coerceAtLeast(1)
        val width = sourceWidth.takeIf { it > 0 } ?: 16
        val height = sourceHeight.takeIf { it > 0 } ?: 9
        val scale = minOf(maxWidth.toFloat() / width, maxHeight.toFloat() / height)
        setMeasuredDimension(
            (width * scale).toInt().coerceIn(1, maxWidth),
            (height * scale).toInt().coerceIn(1, maxHeight)
        )
    }
}

@Composable
private fun SocialCommentsDialog(
    post: SocialPost,
    repository: SocialRepository,
    onDismiss: () -> Unit,
    onError: (String) -> Unit
) {
    val scope = rememberCoroutineScope()
    var comments by remember(post.ownerUid, post.id) { mutableStateOf<List<SocialComment>>(emptyList()) }
    var commentText by remember(post.ownerUid, post.id) { mutableStateOf("") }
    var isLoading by remember(post.ownerUid, post.id) { mutableStateOf(true) }
    var isSending by remember { mutableStateOf(false) }
    var commentError by remember { mutableStateOf<String?>(null) }

    LaunchedEffect(post.ownerUid, post.id) {
        isLoading = true
        runCatching { repository.loadComments(post) }
            .onSuccess { comments = it }
            .onFailure { commentError = "No se pudieron cargar los comentarios." }
        isLoading = false
    }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Surface(
            color = Color(0xFF111827),
            shape = RoundedCornerShape(22.dp),
            modifier = Modifier.fillMaxWidth().padding(horizontal = 16.dp).heightIn(max = 680.dp).testTag("social_comments_dialog")
        ) {
            Column(Modifier.padding(16.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text("Comentarios", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 18.sp, modifier = Modifier.weight(1f))
                    IconButton(onClick = onDismiss) { Icon(Icons.Default.Close, contentDescription = "Cerrar comentarios", tint = Color.White) }
                }
                if (commentError != null) Text(commentError.orEmpty(), color = Color(0xFFFDA4AF), fontSize = 12.sp)
                if (isLoading) {
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        CircularProgressIndicator(color = Color(0xFFE1306C))
                    }
                } else if (comments.isEmpty()) {
                    Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                        Text("Sé la primera persona en comentar.", color = Color(0xFF94A3B8))
                    }
                } else {
                    LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        items(comments, key = { it.id }) { comment ->
                            Column {
                                Text(
                                    comment.authorDisplayName.ifBlank { "@${comment.authorUsername}" }.ifBlank { "Usuario" },
                                    color = Color.White,
                                    fontSize = 12.sp,
                                    fontWeight = FontWeight.Bold
                                )
                                Text(comment.text, color = Color(0xFFE2E8F0), fontSize = 13.sp, modifier = Modifier.padding(top = 2.dp))
                            }
                        }
                    }
                }
                OutlinedTextField(
                    value = commentText,
                    onValueChange = { commentText = it.take(1000) },
                    modifier = Modifier.fillMaxWidth().padding(top = 12.dp).testTag("social_comment_input"),
                    label = { Text("Escribe un comentario") },
                    maxLines = 4
                )
                Button(
                    onClick = {
                        if (isSending || !SocialComment.isValidBody(commentText)) return@Button
                        isSending = true
                        scope.launch {
                            runCatching { repository.addComment(post, commentText) }
                                .onSuccess { comments = (comments + it).sortedBy { comment -> comment.createdAt }; commentText = ""; commentError = null }
                                .onFailure {
                                    commentError = "No se pudo publicar el comentario."
                                    onError("No se pudo publicar el comentario.")
                                }
                            isSending = false
                        }
                    },
                    enabled = !isSending && SocialComment.isValidBody(commentText),
                    modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE1306C))
                ) {
                    Text(if (isSending) "Publicando…" else "Comentar")
                }
            }
        }
    }
}

@Composable
private fun SearchProfileRow(
    profile: SocialProfile,
    isSelf: Boolean,
    followStatus: String,
    onOpen: () -> Unit,
    onFollow: () -> Unit
) {
    Surface(color = Color(0xFF111827), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 14.dp, vertical = 3.dp)) {
        Row(Modifier.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
            AvatarCircle(name = profile.displayName, color = Color(0xFFE1306C), size = 42, imageUrl = profile.avatarUrl)
            Column(Modifier.weight(1f).padding(start = 10.dp).clickable(onClick = onOpen)) {
                Text(profile.displayName, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 13.sp)
                Text("@${profile.username}", color = Color(0xFF94A3B8), fontSize = 11.sp)
                if (profile.isPrivate) Text("Cuenta privada", color = Color(0xFFFBBF24), fontSize = 10.sp)
            }
            if (!isSelf) {
                TextButton(onClick = onFollow) {
                    Text(
                        text = when (followStatus) {
                            "accepted" -> "Siguiendo"
                            "pending" -> "Solicitado"
                            else -> "Seguir"
                        },
                        color = if (followStatus == "") Color(0xFFF472B6) else Color(0xFFCBD5E1),
                        fontWeight = FontWeight.Bold
                    )
                }
            }
        }
    }
}

@Composable
private fun ViewedProfileContent(profile: SocialProfile, posts: List<SocialPost>, repository: SocialRepository, followStatus: String, onFollow: () -> Unit) {
    LazyColumn(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        item {
            Surface(color = Color(0xFF111827), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().padding(12.dp)) {
                Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.padding(20.dp)) {
                    AvatarCircle(name = profile.displayName, color = Color(0xFF7C3AED), size = 72, imageUrl = profile.avatarUrl)
                    Text(profile.displayName, color = Color.White, fontSize = 19.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 10.dp))
                    Text("@${profile.username}", color = Color(0xFF94A3B8), fontSize = 12.sp)
                    Text(if (profile.isPrivate) "Perfil privado" else "Perfil público", color = Color(0xFFCBD5E1), fontSize = 11.sp, modifier = Modifier.padding(top = 6.dp))
                    if (profile.bio.isNotBlank()) Text(profile.bio, color = Color(0xFFE2E8F0), fontSize = 13.sp, modifier = Modifier.padding(top = 8.dp))
                    Button(
                        onClick = onFollow,
                        colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE1306C)),
                        modifier = Modifier.padding(top = 12.dp)
                    ) {
                        Text(when (followStatus) { "accepted" -> "Dejar de seguir"; "pending" -> "Cancelar solicitud"; else -> "Seguir" })
                    }
                }
            }
        }
        if (profile.isPrivate && followStatus != "accepted") {
            item { Text("Las publicaciones se muestran cuando el usuario acepta tu solicitud.", color = Color(0xFF94A3B8), fontSize = 12.sp, modifier = Modifier.padding(horizontal = 18.dp)) }
        } else {
            items(posts, key = { "${it.ownerUid}:${it.id}" }) { post ->
                SocialPostCard(post = post, repository = repository, liked = false, onLike = {}, onAuthorClick = {})
            }
        }
    }
}

@Composable
private fun MyProfileCard(profile: SocialProfile?, onEdit: () -> Unit, onVisibilityChanged: (Boolean) -> Unit) {
    if (profile == null) return
    Surface(color = Color(0xFF111827), shape = RoundedCornerShape(18.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 10.dp)) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                AvatarCircle(name = profile.displayName, color = Color(0xFFE1306C), size = 64, imageUrl = profile.avatarUrl)
                Column(Modifier.weight(1f).padding(start = 12.dp)) {
                    Text(profile.displayName, color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold)
                    Text("@${profile.username}", color = Color(0xFF94A3B8), fontSize = 12.sp)
                    Text(if (profile.isPrivate) "Solo seguidores aprobados verán tus publicaciones" else "Tu perfil es visible para la comunidad", color = Color(0xFFCBD5E1), fontSize = 10.sp, modifier = Modifier.padding(top = 4.dp))
                }
            }
            TextButton(onClick = onEdit, modifier = Modifier.padding(top = 2.dp)) {
                Text("Editar perfil", color = Color(0xFFF472B6))
            }
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().padding(top = 12.dp)) {
                Icon(if (profile.isPrivate) Icons.Default.Lock else Icons.Default.Public, contentDescription = null, tint = Color(0xFFF472B6), modifier = Modifier.size(18.dp))
                Text(if (profile.isPrivate) "Perfil privado" else "Perfil público", color = Color.White, fontSize = 13.sp, modifier = Modifier.weight(1f).padding(start = 8.dp))
                TextButton(
                    onClick = { onVisibilityChanged(profile.isPrivate) },
                    modifier = Modifier.testTag("social_profile_visibility")
                ) {
                    Text(if (profile.isPrivate) "Hacer público" else "Hacer privado", color = Color(0xFFF472B6))
                }
            }
        }
    }
}

@Composable
private fun FollowRequestsCard(requests: List<SocialFollowRequest>, onAccept: (SocialFollowRequest) -> Unit) {
    Surface(color = Color(0xFF20172B), shape = RoundedCornerShape(14.dp), modifier = Modifier.fillMaxWidth().padding(horizontal = 12.dp)) {
        Column(Modifier.padding(12.dp)) {
            Text("Solicitudes para seguirte", color = Color.White, fontWeight = FontWeight.Bold, fontSize = 13.sp)
            requests.forEach { request ->
                Row(Modifier.fillMaxWidth().padding(top = 8.dp), verticalAlignment = Alignment.CenterVertically) {
                    Text("${request.displayName} · @${request.username}", color = Color(0xFFCBD5E1), fontSize = 11.sp, modifier = Modifier.weight(1f))
                    TextButton(onClick = { onAccept(request) }) { Text("Aceptar", color = Color(0xFFF472B6)) }
                }
            }
        }
    }
}

@Composable
private fun EmptySocialFeed(isFollowing: Boolean, onCreate: () -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 48.dp),
        horizontalAlignment = Alignment.CenterHorizontally
    ) {
        AvatarCircle(name = "Social", color = Color(0xFF4C1D3D), size = 64)
        Text(if (isFollowing) "Tu feed está esperando" else "Empieza tu comunidad", color = Color.White, fontSize = 18.sp, fontWeight = FontWeight.Bold, modifier = Modifier.padding(top = 14.dp))
        Text(
            if (isFollowing) "Sigue perfiles para ver sus publicaciones aquí." else "Publica una idea con #temas y tus likes ayudarán a ordenar recomendaciones.",
            color = Color(0xFF94A3B8), fontSize = 12.sp, modifier = Modifier.padding(top = 6.dp)
        )
        Button(onClick = onCreate, colors = ButtonDefaults.buttonColors(containerColor = Color(0xFFE1306C)), modifier = Modifier.padding(top = 14.dp)) {
            Text("Crear publicación")
        }
    }
}

@Composable
private fun AvatarCircle(name: String, color: Color, size: Int, imageUrl: String = "") {
    Surface(color = color.copy(alpha = 0.22f), shape = CircleShape, modifier = Modifier.size(size.dp)) {
        if (imageUrl.isNotBlank()) {
            AsyncImage(
                model = imageUrl,
                contentDescription = "Foto de perfil de $name",
                contentScale = ContentScale.Crop,
                modifier = Modifier.fillMaxSize().clip(CircleShape)
            )
        } else {
            Box(contentAlignment = Alignment.Center) {
                Text(
                    text = name.trim().firstOrNull()?.uppercaseChar()?.toString() ?: "S",
                    color = Color(0xFFF9A8D4),
                    fontWeight = FontWeight.Bold,
                    fontSize = (size / 2.4f).sp
                )
            }
        }
    }
}

private fun relativeTime(timestamp: Long): String {
    if (timestamp <= 0L) return "ahora"
    val minutes = ((System.currentTimeMillis() - timestamp).coerceAtLeast(0L) / 60_000L).toInt()
    return when {
        minutes < 1 -> "ahora"
        minutes < 60 -> "${minutes}m"
        minutes < 24 * 60 -> "${minutes / 60}h"
        else -> SimpleDateFormat("d MMM", Locale("es", "CR")).format(Date(timestamp))
    }
}
