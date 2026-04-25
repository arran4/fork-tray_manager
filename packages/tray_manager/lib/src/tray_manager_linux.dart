import 'dart:async';

import 'package:dart_xdg_status_notifier_item/dart_xdg_status_notifier_item.dart';
import 'package:menu_base/menu_base.dart';
import 'package:shortid/shortid.dart';

class TrayManagerLinux {
  TrayManagerLinux._();

  static final TrayManagerLinux instance = TrayManagerLinux._();

  static void registerWith() {
    TrayManagerLinux.instance;
  }

  StatusNotifierItemClient? _client;
  DBusMenuItem? _currentMenu;
  String _iconName = 'flutter';
  String? _title;
  String? _toolTip;

  // Callbacks to communicate events back to the main TrayManager class
  void Function()? onTrayIconMouseDown;
  void Function()? onTrayIconMouseUp;
  void Function()? onTrayIconRightMouseDown;
  void Function()? onTrayIconRightMouseUp;
  void Function(int id)? onTrayMenuItemClick;
  void Function(int delta, String orientation)? onTrayIconScroll;
  Future<void> _clientOperation = Future.value();

  Future<void> destroy() async {
    await _runClientOperation(() async {
      StatusNotifierItemClient? client = _client;
      _client = null;
      _currentMenu = null;

      if (client != null) {
        await client.close();
      }
    });
  }

  Future<void> setIcon(String iconPath) async {
    await _runClientOperation(() async {
      StatusNotifierItemClient client = await _ensureClient();
      _iconName = iconPath;
      client.iconName = iconPath;
    });
  }

  Future<void> setToolTip(String toolTip) async {
    await _runClientOperation(() async {
      StatusNotifierItemClient client = await _ensureClient();
      _toolTip = toolTip;
      client.toolTip = _buildToolTip(toolTip);
    });
  }

  Future<void> setTitle(String title) async {
    await _runClientOperation(() async {
      StatusNotifierItemClient client = await _ensureClient();
      _title = title;
      client.title = title;
    });
  }

  Future<void> setContextMenu(Menu menu) async {
    await _runClientOperation(() async {
      DBusMenuItem rootMenu = _buildDBusMenu(menu);
      if (_client == null) {
        await _ensureClient(initialMenu: rootMenu);
        return;
      }

      if (_isMenuLayoutCompatible(_currentMenu, rootMenu)) {
        StatusNotifierItemClient client = _client!;
        await client.updateMenu(rootMenu);
        _currentMenu = rootMenu;
        return;
      }

      // TODO(arran4): Replace full client recreation once the DBus menu layer
      // supports structural menu updates.
      await _recreateClientWithMenu(rootMenu);
    });
  }

  DBusMenuItem _buildDBusMenu(Menu menu) {
    return DBusMenuItem(
      children: (menu.items ?? []).map((MenuItem item) {
        if (item.type == 'separator') {
          return DBusMenuItem.separator();
        }

        if (item.type == 'checkbox') {
           return DBusMenuItem.checkmark(
             item.label ?? '',
             enabled: !item.disabled,
             state: item.checked ?? false,
             onClicked: () async {
                onTrayMenuItemClick?.call(item.id);
             },
           );
        }

        if (item.type == 'radio') {
           return DBusMenuItem.radio(
             item.label ?? '',
             enabled: !item.disabled,
             state: item.checked ?? false,
             onClicked: () async {
                onTrayMenuItemClick?.call(item.id);
             },
           );
        }

        return DBusMenuItem(
          label: item.label ?? '',
          enabled: !item.disabled,
          children: item.submenu != null ? _buildDBusMenu(item.submenu!).children : [],
          onClicked: () async {
             onTrayMenuItemClick?.call(item.id);
          },
        );
      }).toList(),
    );
  }

  Future<StatusNotifierItemClient> _ensureClient({DBusMenuItem? initialMenu}) async {
    if (_client != null) {
      return _client!;
    }

    String id = 'tray_manager_${shortid.generate()}';
    DBusMenuItem menu = initialMenu ?? DBusMenuItem(children: []);
    StatusNotifierItemClient client = StatusNotifierItemClient(
        id: id,
        menu: menu,
        onActivate: (x, y) async {
           onTrayIconMouseDown?.call();
           onTrayIconMouseUp?.call();
        },
        onSecondaryActivate: (x, y) async {
           onTrayIconRightMouseDown?.call();
           onTrayIconRightMouseUp?.call();
        },
        onScroll: (delta, orientation) async {
           onTrayIconScroll?.call(delta, orientation);
        },
        onContextMenu: (x, y) async {
           // Provide the menu structure
        },
      );

    _client = client;
    _currentMenu = menu;
    client.iconName = _iconName; // Default fallback
    if (_title != null) {
      client.title = _title!;
    }
    if (_toolTip != null) {
      client.toolTip = _buildToolTip(_toolTip!);
    }

    try {
      await client.connect();
    } catch (_) {
      if (identical(_client, client)) {
        _client = null;
        _currentMenu = null;
      }
      rethrow;
    }

    return client;
  }

  Future<void> _recreateClientWithMenu(DBusMenuItem menu) async {
    StatusNotifierItemClient? client = _client;
    _client = null;
    _currentMenu = null;

    if (client != null) {
      await client.close();
    }

    await _ensureClient(initialMenu: menu);
  }

  Future<T> _runClientOperation<T>(Future<T> Function() operation) {
    Completer<T> completer = Completer<T>();
    _clientOperation = _clientOperation.catchError((_) {}).then((_) async {
      try {
        T result = await operation();
        completer.complete(result);
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  StatusNotifierToolTip _buildToolTip(String toolTip) {
    return StatusNotifierToolTip(
      iconName: _iconName,
      iconPixmap: [],
      title: toolTip,
      body: '',
    );
  }

  bool _isMenuLayoutCompatible(DBusMenuItem? previous, DBusMenuItem next) {
    if (previous == null) {
      return false;
    }

    List<DBusMenuItem> previousChildren = previous.children;
    List<DBusMenuItem> nextChildren = next.children;
    if (previousChildren.length != nextChildren.length) {
      return false;
    }

    for (int i = 0; i < previousChildren.length; i++) {
      if (!_isMenuLayoutCompatible(previousChildren[i], nextChildren[i])) {
        return false;
      }
    }

    return true;
  }
}
