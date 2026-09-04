import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/chat_read_store.dart';
import '../utils/helpers.dart';
import '../utils/network.dart';
import '../widgets/app_widgets.dart';
import '../widgets/customer_ui_components.dart';

class ChatInboxScreen extends StatefulWidget {
  const ChatInboxScreen({super.key});

  @override
  State<ChatInboxScreen> createState() => _ChatInboxScreenState();
}

class _ChatInboxScreenState extends State<ChatInboxScreen> {
  final _supabase = Supabase.instance.client;
  bool _loading = true;
  String? _error;
  List<ChatInboxItem> _rooms = const [];
  Map<String, DateTime> _lastRead = const {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Sign in to see your Order# chats.';
          _rooms = const [];
        });
      }
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final myId = user.id;
      final results = await Future.wait([
        _supabase
            .from('orders')
            .select('id, order_id, chef_id, customer_id, user_id, driver_id, delivery_partner_id, created_at')
            .or('customer_id.eq.$myId,user_id.eq.$myId,chef_id.eq.$myId,driver_id.eq.$myId,delivery_partner_id.eq.$myId')
            .order('created_at', ascending: false)
            .limit(80),
        _supabase
            .from('customer_requests')
            .select('id, title, customer_id, accepted_chef_id, created_at')
            .or('customer_id.eq.$myId,accepted_chef_id.eq.$myId')
            .order('created_at', ascending: false)
            .limit(40),
        _supabase
            .from('messages')
            .select('meal_id, content, created_at, sender_id')
            .eq('sender_id', myId)
            .order('created_at', ascending: false)
            .limit(120),
      ]);

      final orders = _asMaps(results[0]);
      final requests = _asMaps(results[1]);
      final sent = _asMaps(results[2]);

      final roomIds = <String>{
        ...orders.map(orderChatRoomId).where((id) => id.isNotEmpty),
        ...requests.map((row) => row['id']?.toString() ?? '').where((id) => id.isNotEmpty),
      }.toList();

      var messages = sent;
      if (roomIds.isNotEmpty) {
        final roomMessages = _asMaps(await _supabase
            .from('messages')
            .select('meal_id, content, created_at, sender_id')
            .inFilter('meal_id', roomIds)
            .order('created_at', ascending: false)
            .limit(200));
        messages = [...roomMessages, ...sent];
      }

      final rooms = mergeChatInboxRooms(
        myId: myId,
        orders: orders,
        requests: requests,
        messages: messages,
      );

      final lastRead = await ChatReadStore.lastReadByRoom(rooms.map((room) => room.roomId));

      if (!mounted) return;
      setState(() {
        _rooms = rooms;
        _lastRead = lastRead;
        _loading = false;
      });
    } catch (e, stack) {
      FirebaseCrashlytics.instance.recordError(e, stack, reason: 'Chat inbox load failure');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = networkErrorMessage(e);
      });
    }
  }

  List<Map<String, dynamic>> _asMaps(dynamic rows) {
    if (rows is! List) return const [];
    return rows.whereType<Map>().map((row) => Map<String, dynamic>.from(row)).toList();
  }

  String _stamp(DateTime? at) {
    if (at == null) return '';
    final local = at.toLocal();
    final now = DateTime.now();
    if (local.year == now.year && local.month == now.month && local.day == now.day) {
      return DateFormat.jm().format(local);
    }
    return DateFormat('d MMM').format(local);
  }

  @override
  Widget build(BuildContext context) {
    final ink = AppTheme.onSurfaceOf(context);
    return Scaffold(
      backgroundColor: AppTheme.canvasOf(context),
      appBar: HubAppBar(title: 'Order chats'),
      body: RefreshIndicator(
        color: AppTheme.primary,
        onRefresh: _load,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                  SizedBox(height: 180),
                  Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                ],
              )
            : _error != null
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: MediaQuery.of(context).size.height * 0.6,
                        child: EmptyState(
                          icon: Icons.wifi_off_rounded,
                          title: 'Couldn\'t load chats',
                          message: _error,
                          actionLabel: 'Retry',
                          onAction: _load,
                        ),
                      ),
                    ],
                  )
                : _rooms.isEmpty
                    ? ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(height: 80),
                          EmptyState(
                            icon: Icons.forum_outlined,
                            title: 'No Order# chats yet',
                            message: 'Open an order, leftover, or catering lead and the group will show up here.',
                          ),
                        ],
                      )
                    : ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                        itemCount: _rooms.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final room = _rooms[index];
                          return Material(
                            color: AppTheme.surfaceOf(context),
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () async {
                                await ChatReadStore.markRead(room.roomId);
                                if (!context.mounted) return;
                                await context.push(chatPath(
                                  room.roomId,
                                  roomName: room.title,
                                  otherUserId: room.otherUserId,
                                  memberIds: room.memberIds,
                                  isGroup: room.isGroup,
                                ));
                                if (mounted) _load();
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: AppTheme.hairlineOf(context)),
                                ),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                                      child: Icon(
                                        room.isGroup ? Icons.forum_outlined : Icons.chat_bubble_outline,
                                        color: AppTheme.primary,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            room.title,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: ink, fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            room.preview,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(color: ink.withValues(alpha: 0.65), fontSize: 13),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Column(
                                      crossAxisAlignment: CrossAxisAlignment.end,
                                      children: [
                                        Text(
                                          _stamp(room.lastAt),
                                          style: TextStyle(color: ink.withValues(alpha: 0.5), fontSize: 11, fontWeight: FontWeight.w600),
                                        ),
                                        const SizedBox(height: 6),
                                        UnreadChatIndicator(
                                          mealId: room.roomId,
                                          hasUnread: chatRoomHasUnread(
                                            myId: _supabase.auth.currentUser?.id ?? '',
                                            lastAt: room.lastAt,
                                            lastSenderId: room.lastSenderId,
                                            lastReadAt: _lastRead[room.roomId],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
      ),
    );
  }
}
