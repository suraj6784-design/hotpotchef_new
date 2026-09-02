// lib/screens/in_app_chat_screen.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:intl/intl.dart';

import '../services/alert_service.dart';
import '../utils/app_theme.dart';
import '../utils/network.dart';

class InAppChatScreen extends StatefulWidget {
  final String mealId;
  final String roomName;

  const InAppChatScreen({
    super.key,
    required this.mealId,
    required this.roomName,
  });

  @override
  State<InAppChatScreen> createState() => _InAppChatScreenState();
}

class _InAppChatScreenState extends State<InAppChatScreen> {
  final _supabase = Supabase.instance.client;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  
  // Cache System
  final Map<String, String> _roleCache = {};
  bool _isFetchingRoles = false;

  @override
  void initState() {
    super.initState();
    ChatAlertScope.activeMealId = widget.mealId;
  }

  @override
  void dispose() {
    if (ChatAlertScope.activeMealId == widget.mealId) {
      ChatAlertScope.activeMealId = null;
    }
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // --- Batch Role Resolution ---

  Future<void> _batchFetchRoles(List<String> userIds) async {
    if (userIds.isEmpty || _isFetchingRoles) return;
    _isFetchingRoles = true;

    try {
      final response = await _supabase
          .from('users')
          .select('id, role')
          .inFilter('id', userIds);

      if (mounted) {
        setState(() {
          for (var row in response) {
            final id = row['id']?.toString() ?? '';
            final role = row['role']?.toString() ?? 'Support';
            if (id.isNotEmpty) {
              _roleCache[id] = role;
            }
          }
        });
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Batch role fetch failed in chat');
    } finally {
      _isFetchingRoles = false;
    }
  }

  // --- Send Message Pipeline ---

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    final user = _supabase.auth.currentUser;
    if (user == null) return;

    try {
      final inserted = await _supabase.from('messages').insert({
        'meal_id': widget.mealId,
        'sender_id': user.id,
        'content': text,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }).select('id').maybeSingle();
      final messageId = inserted?['id']?.toString();
      if (messageId != null) AlertService.notifyChat(messageId: messageId);
      
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to send chat message');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(networkErrorMessage(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- UI Tree ---

  @override
  Widget build(BuildContext context) {
    final currentUserId = _supabase.auth.currentUser?.id;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppTheme.backgroundDark : AppTheme.background;
    final surface = isDark ? AppTheme.surfaceDark : AppTheme.surfaceLight;
    final titleColor = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final muted = isDark ? Colors.grey.shade400 : AppTheme.textMuted;
    final otherBubble = isDark ? AppTheme.surfaceMutedDark : AppTheme.surfaceMutedLight;
    final otherText = isDark ? AppTheme.textMainDark : AppTheme.textMain;
    final composerFill = isDark ? AppTheme.surfaceMutedDark : AppTheme.surfaceMutedLight;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(
          widget.roomName,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: titleColor),
        ),
        elevation: 0,
        iconTheme: IconThemeData(color: titleColor),
      ),
      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('messages')
                  .stream(primaryKey: ['id'])
                  .eq('meal_id', widget.mealId)
                  .order('created_at', ascending: false),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                }
                if (!snapshot.hasData || snapshot.data!.isEmpty) {
                  return Center(
                    child: Text(
                      'No messages yet.\nStart the conversation securely!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: muted),
                    ),
                  );
                }

                final messages = snapshot.data!;

                // Identify missing sender roles and batch-fetch via post-frame callback
                final missingSenders = messages
                    .map((m) => m['sender_id']?.toString() ?? '')
                    .where((id) => id.isNotEmpty && id != currentUserId && !_roleCache.containsKey(id))
                    .toSet()
                    .toList();

                if (missingSenders.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    _batchFetchRoles(missingSenders);
                  });
                }

                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: const EdgeInsets.all(16),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final isMe = msg['sender_id'] == currentUserId;
                    final sId = msg['sender_id']?.toString().trim() ?? '';

                    String senderRole = 'Support';
                    Color roleColor = Colors.grey;
                    IconData roleIcon = Icons.support_agent;

                    if (!isMe && sId.isNotEmpty) {
                      final dbRole = (_roleCache[sId] ?? 'Support').toLowerCase();

                      if (dbRole == 'chef') {
                        senderRole = 'Chef';
                        roleColor = Colors.orange;
                        roleIcon = Icons.restaurant;
                      } else if (dbRole == 'driver') {
                        senderRole = 'Delivery Partner';
                        roleColor = Colors.blue;
                        roleIcon = Icons.two_wheeler;
                      } else if (dbRole == 'customer') {
                        senderRole = 'Customer';
                        roleColor = Colors.teal;
                        roleIcon = Icons.person;
                      } else {
                        senderRole = _roleCache[sId] ?? 'Support';
                      }
                    }

                    String timeStr = '';
                    if (msg['created_at'] != null) {
                      try {
                        final dt = DateTime.parse(msg['created_at']).toLocal();
                        timeStr = DateFormat('hh:mm a').format(dt);
                      } catch (e, stack) {
                        FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Failed to parse chat message timestamp');
                      }
                    }

                    return Align(
                      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
                        child: Column(
                          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                          children: [
                            if (!isMe)
                              Padding(
                                padding: const EdgeInsets.only(left: 4, bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(roleIcon, size: 10, color: roleColor),
                                    const SizedBox(width: 4),
                                    Text(
                                      senderRole.toUpperCase(),
                                      style: TextStyle(
                                        color: roleColor,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: isMe ? AppTheme.primary : otherBubble,
                                borderRadius: BorderRadius.only(
                                  topLeft: const Radius.circular(16),
                                  topRight: const Radius.circular(16),
                                  bottomLeft: Radius.circular(isMe ? 16 : 4),
                                  bottomRight: Radius.circular(isMe ? 4 : 16),
                                ),
                              ),
                              child: Text(
                                msg['content'] ?? '',
                                style: TextStyle(
                                  color: isMe ? Colors.white : otherText,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                            if (timeStr.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 4, right: 4, left: 4),
                                child: Text(timeStr, style: TextStyle(color: muted, fontSize: 9)),
                              )
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: surface,
              border: Border(top: BorderSide(color: isDark ? Colors.black26 : Colors.black12)),
            ),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      style: TextStyle(color: titleColor),
                      decoration: InputDecoration(
                        hintText: 'Message securely...',
                        hintStyle: TextStyle(color: muted),
                        filled: true,
                        fillColor: composerFill,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      minLines: 1,
                      maxLines: 4,
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _sendMessage,
                    child: const CircleAvatar(
                      radius: 22,
                      backgroundColor: AppTheme.primary,
                      child: Icon(Icons.send, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
