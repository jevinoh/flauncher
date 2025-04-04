/*
 * FLauncher
 * Copyright (C) 2021  Étienne Fesser
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

import 'dart:io';

import 'package:flauncher/flauncher_channel.dart';
import 'package:flauncher/gradients.dart';
import 'package:flauncher/providers/settings_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';

import '../utils.dart';

class WallpaperService extends ChangeNotifier {
  final FLauncherChannel _fLauncherChannel;
  final SettingsService _settingsService;

  late File _wallpaperFile;

  ImageProvider? _wallpaper;

  ImageProvider?  get wallpaper     => _wallpaper;

  FLauncherGradient get gradient => FLauncherGradients.all.firstWhere(
        (gradient) => gradient.uuid == _settingsService.gradientUuid,
        orElse: () => FLauncherGradients.greatWhale,
      );

  WallpaperService(this._fLauncherChannel, this._settingsService) :
    _wallpaper = null
  {
    _init();
  }

  Future<void> _init() async {
    final directory = await getApplicationDocumentsDirectory();
    logDebug("App directory: ${directory.path}");

    _wallpaperFile = File("${directory.path}/tv_background.jpg");

    if (await _wallpaperFile.exists()) {
      logDebug("Using user-selected wallpaper");
      _wallpaper = FileImage(_wallpaperFile);
    } else {
      logDebug("Using default asset wallpaper");
      try {
        ByteData assetData = await rootBundle.load('assets/tv_background.jpg');
        Uint8List bytes = assetData.buffer.asUint8List();

        // Save asset wallpaper to file for future use
        await _wallpaperFile.writeAsBytes(bytes);

        _wallpaper = MemoryImage(bytes);
      } catch (e) {
        logDebug("Failed to load asset wallpaper: $e");
      }
    }

    notifyListeners();
  }

  Future<void> pickWallpaper() async {
    if (!await _fLauncherChannel.checkForGetContentAvailability()) {
      throw NoFileExplorerException();
    }

    final imagePicker = ImagePicker();
    final pickedFile = await imagePicker.pickImage(source: ImageSource.gallery);

    if (pickedFile != null) {
      Uint8List bytes = await pickedFile.readAsBytes();
      await _wallpaperFile.writeAsBytes(bytes);

      _wallpaper = MemoryImage(bytes);
      logDebug("User-selected wallpaper updated");

      notifyListeners();
    }
  }

  Future<void> setGradient(FLauncherGradient fLauncherGradient) async {
    if (await _wallpaperFile.exists()) {
      await _wallpaperFile.delete();
    }

    _settingsService.setGradientUuid(fLauncherGradient.uuid);
    notifyListeners();
  }
}

class NoFileExplorerException implements Exception {}
