// SPDX-FileCopyrightText: 2026 Cruyfford
// SPDX-License-Identifier: GPL-3.0

// iOS: no libcurl. Online features (cover download, achievements) are disabled for now.

#include "http_downloader.h"

std::unique_ptr<HTTPDownloader> HTTPDownloader::Create(std::string user_agent)
{
  return {};
}
